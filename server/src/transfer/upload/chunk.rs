// 分片上传：大文件切分为多个分片上传，服务端暂存后拼接合并
//
// 协议（挂在 /api/transfer/upload 下）：
//   GET  /policy                    → 返回服务器分片大小策略 { chunk_size, chunk_size_mb }
//   POST /chunk/init                → 创建分片会话，返回 upload_id
//   POST /chunk/part/{id}/{index}   → 上传单个分片（裸二进制 body，流式写盘）
//   GET  /chunk/status/{id}         → 查询已收分片（断点续传）
//   POST /chunk/complete/{id}       → 按序拼接分片，写入目标目录并索引
//   POST /chunk/abort/{id}          → 取消并清理暂存分片
//
// 设计说明：分片先暂存到 app_dir/uploads_staging/<upload_id>/，complete 时顺序拼接到
// 目标文件夹（复用与直传一致的同名去重命名规则），合并成功后清理暂存目录。
// 会话元数据保存在内存中（与 TaskManager 一致），进程存活期内支持断点续传。

use actix_web::{web, HttpResponse, Result};
use futures_util::StreamExt;
use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::io::AsyncWriteExt;
use tokio::sync::Mutex;

use super::storage;

/// 默认分片大小（MB）——app.json 未配置时使用
const DEFAULT_CHUNK_SIZE_MB: u64 = 30;

/// 单个分片会话
#[derive(Clone)]
struct ChunkSession {
    file_name: String,
    file_size: u64,
    target_folder: String,
    total_chunks: u32,
    received: HashSet<u32>,
    created_at: String,
}

/// 分片会话管理器（内存态，注册为 actix app_data）
pub struct ChunkUploadManager {
    sessions: Arc<Mutex<HashMap<String, ChunkSession>>>,
}

impl ChunkUploadManager {
    pub fn new() -> Self {
        ChunkUploadManager {
            sessions: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// 创建会话，返回 upload_id
    async fn create(&self, session: ChunkSession) -> String {
        let upload_id = uuid::Uuid::new_v4().to_string();
        self.sessions.lock().await.insert(upload_id.clone(), session);
        upload_id
    }

    /// 获取会话副本
    async fn get(&self, upload_id: &str) -> Option<ChunkSession> {
        self.sessions.lock().await.get(upload_id).cloned()
    }

    /// 标记某分片已接收
    async fn mark_received(&self, upload_id: &str, index: u32) -> bool {
        if let Some(s) = self.sessions.lock().await.get_mut(upload_id) {
            s.received.insert(index);
            true
        } else {
            false
        }
    }

    /// 移除会话
    async fn remove(&self, upload_id: &str) {
        self.sessions.lock().await.remove(upload_id);
    }
}

impl Default for ChunkUploadManager {
    fn default() -> Self {
        Self::new()
    }
}

/// 某会话的暂存目录
fn stage_dir_for(upload_id: &str) -> PathBuf {
    crate::static_files::app_dir()
        .join("uploads_staging")
        .join(upload_id)
}

/// 单个分片文件路径
fn part_path(stage_dir: &Path, index: u32) -> PathBuf {
    stage_dir.join(format!("{:06}.part", index))
}

/// 从 app.json 读取分片大小限制（MB），无配置则回退默认值
fn read_chunk_size_mb() -> u64 {
    if let Some(data) = crate::static_files::read_config_file("app.json") {
        if let Ok(v) = serde_json::from_slice::<serde_json::Value>(&data) {
            if let Some(n) = v.get("upload_chunk_size_mb").and_then(|x| x.as_u64()) {
                if n > 0 {
                    return n;
                }
            }
        }
    }
    DEFAULT_CHUNK_SIZE_MB
}

/// 同名去重：若目标文件已存在，用「指数搜索 + 二分搜索」找最小可用序号
/// （与 task_manager 直传逻辑保持一致）
fn resolve_available_path(target_folder: &str, file_name: &str) -> PathBuf {
    let base_path = Path::new(target_folder).join(file_name);
    if !base_path.exists() {
        return base_path;
    }
    let stem = Path::new(file_name)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(file_name)
        .to_string();
    let ext = Path::new(file_name)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| format!(".{}", e))
        .unwrap_or_default();
    let candidate = |n: u32| -> PathBuf {
        Path::new(target_folder).join(format!("{}({}){}", stem, n, ext))
    };
    let mut hi: u32 = 1;
    while candidate(hi).exists() {
        hi = hi.saturating_mul(2);
        if hi >= 1_000_000 {
            break;
        }
    }
    let mut lo: u32 = hi / 2 + 1;
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        if candidate(mid).exists() {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    candidate(lo)
}

// MARK: - Handlers

/// GET /api/transfer/upload/policy
/// 返回服务器端分片大小策略，客户端据此决定直传或分片
pub async fn get_upload_policy() -> Result<HttpResponse> {
    let mb = read_chunk_size_mb();
    let bytes = mb.saturating_mul(1024 * 1024);
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "chunk_size": bytes,
        "chunk_size_mb": mb,
    })))
}

/// 初始化分片会话请求
#[derive(Deserialize)]
pub struct InitChunkRequest {
    pub file_name: String,
    #[serde(default)]
    pub file_size: u64,
    pub target_folder: String,
    pub total_chunks: u32,
}

/// POST /api/transfer/upload/chunk/init
/// 创建分片上传会话
pub async fn init_chunk_upload(
    body: web::Json<InitChunkRequest>,
    manager: web::Data<ChunkUploadManager>,
) -> Result<HttpResponse> {
    let req = body.into_inner();

    if req.target_folder.trim().is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "目标文件夹未指定"
        })));
    }
    if req.file_name.trim().is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "文件名缺失"
        })));
    }
    if req.total_chunks == 0 {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "分片数量无效"
        })));
    }

    let session = ChunkSession {
        file_name: req.file_name.clone(),
        file_size: req.file_size,
        target_folder: req.target_folder.clone(),
        total_chunks: req.total_chunks,
        received: HashSet::new(),
        created_at: chrono::Utc::now().to_rfc3339(),
    };

    let upload_id = manager.create(session).await;

    // 创建暂存目录
    let stage_dir = stage_dir_for(&upload_id);
    if let Err(e) = tokio::fs::create_dir_all(&stage_dir).await {
        manager.remove(&upload_id).await;
        return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("无法创建暂存目录: {}", e)
        })));
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "upload_id": upload_id,
        "total_chunks": req.total_chunks,
    })))
}

/// POST /api/transfer/upload/chunk/part/{upload_id}/{index}
/// 上传单个分片（body 为裸二进制，流式写盘，index 从 0 起）
pub async fn upload_chunk_part(
    path: web::Path<(String, u32)>,
    mut payload: web::Payload,
    manager: web::Data<ChunkUploadManager>,
) -> Result<HttpResponse> {
    let (upload_id, index) = path.into_inner();

    let session = match manager.get(&upload_id).await {
        Some(s) => s,
        None => {
            return Ok(HttpResponse::NotFound().json(serde_json::json!({
                "error": "上传会话不存在或已过期"
            })));
        }
    };

    if index >= session.total_chunks {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "分片序号越界"
        })));
    }

    let stage_dir = stage_dir_for(&upload_id);
    if let Err(e) = tokio::fs::create_dir_all(&stage_dir).await {
        return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("无法创建暂存目录: {}", e)
        })));
    }

    // 先写入临时文件，完成后原子改名，避免半截分片被当作有效分片
    let final_path = part_path(&stage_dir, index);
    let tmp_path = stage_dir.join(format!("{:06}.part.tmp", index));

    let mut file = match tokio::fs::File::create(&tmp_path).await {
        Ok(f) => f,
        Err(e) => {
            return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                "error": format!("无法创建分片文件: {}", e)
            })));
        }
    };

    let mut written: u64 = 0;
    while let Some(chunk) = payload.next().await {
        match chunk {
            Ok(data) => {
                if let Err(e) = file.write_all(&data).await {
                    let _ = tokio::fs::remove_file(&tmp_path).await;
                    return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                        "error": format!("写入分片失败: {}", e)
                    })));
                }
                written += data.len() as u64;
            }
            Err(e) => {
                let _ = tokio::fs::remove_file(&tmp_path).await;
                return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                    "error": format!("读取分片数据失败: {}", e)
                })));
            }
        }
    }

    if let Err(e) = file.flush().await {
        let _ = tokio::fs::remove_file(&tmp_path).await;
        return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("刷新分片失败: {}", e)
        })));
    }
    drop(file);

    if let Err(e) = tokio::fs::rename(&tmp_path, &final_path).await {
        let _ = tokio::fs::remove_file(&tmp_path).await;
        return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("保存分片失败: {}", e)
        })));
    }

    manager.mark_received(&upload_id, index).await;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "index": index,
        "received": written,
    })))
}

/// GET /api/transfer/upload/chunk/status/{upload_id}
/// 查询已接收分片序号列表（用于断点续传）
pub async fn get_chunk_status(
    path: web::Path<String>,
    manager: web::Data<ChunkUploadManager>,
) -> Result<HttpResponse> {
    let upload_id = path.into_inner();
    match manager.get(&upload_id).await {
        Some(s) => {
            let mut uploaded: Vec<u32> = s.received.iter().copied().collect();
            uploaded.sort_unstable();
            Ok(HttpResponse::Ok().json(serde_json::json!({
                "upload_id": upload_id,
                "total_chunks": s.total_chunks,
                "file_size": s.file_size,
                "uploaded": uploaded,
            })))
        }
        None => Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": "上传会话不存在或已过期"
        }))),
    }
}

/// POST /api/transfer/upload/chunk/complete/{upload_id}
/// 按序拼接所有分片，写入目标文件夹并触发索引
pub async fn complete_chunk_upload(
    path: web::Path<String>,
    manager: web::Data<ChunkUploadManager>,
) -> Result<HttpResponse> {
    let upload_id = path.into_inner();

    let session = match manager.get(&upload_id).await {
        Some(s) => s,
        None => {
            return Ok(HttpResponse::NotFound().json(serde_json::json!({
                "error": "上传会话不存在或已过期"
            })));
        }
    };

    // 校验分片完整性：全部分片必须已接收
    if session.received.len() != session.total_chunks as usize {
        let missing: Vec<u32> = (0..session.total_chunks)
            .filter(|i| !session.received.contains(i))
            .collect();
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "分片不完整",
            "missing": missing,
        })));
    }

    let stage_dir = stage_dir_for(&upload_id);

    // 确保目标目录存在
    if let Err(e) = tokio::fs::create_dir_all(&session.target_folder).await {
        return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("无法创建目标文件夹: {}", e)
        })));
    }

    // 解析可用文件路径（同名去重）
    let file_path = resolve_available_path(&session.target_folder, &session.file_name);

    // 创建目标文件
    let mut out = match tokio::fs::File::create(&file_path).await {
        Ok(f) => f,
        Err(e) => {
            return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                "error": format!("无法创建文件: {}", e)
            })));
        }
    };

    // 按序拼接分片
    let mut total_size: u64 = 0;
    for i in 0..session.total_chunks {
        let p = part_path(&stage_dir, i);
        let mut part_file = match tokio::fs::File::open(&p).await {
            Ok(f) => f,
            Err(e) => {
                let _ = tokio::fs::remove_file(&file_path).await;
                return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                    "error": format!("读取分片 {} 失败: {}", i, e)
                })));
            }
        };
        match tokio::io::copy(&mut part_file, &mut out).await {
            Ok(n) => total_size += n,
            Err(e) => {
                let _ = tokio::fs::remove_file(&file_path).await;
                return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                    "error": format!("拼接分片 {} 失败: {}", i, e)
                })));
            }
        }
    }

    if let Err(e) = out.flush().await {
        let _ = tokio::fs::remove_file(&file_path).await;
        return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("刷新文件失败: {}", e)
        })));
    }
    drop(out);

    // 清理暂存目录 + 会话
    let _ = tokio::fs::remove_dir_all(&stage_dir).await;
    manager.remove(&upload_id).await;

    // 触发文件索引（与直传 complete_task 一致的流程）
    let file_path_str = file_path.to_string_lossy().to_string();
    let file_name = session.file_name.clone();
    let target_folder = session.target_folder.clone();
    let file_path_clone = file_path_str.clone();
    let file_name_clone = file_name.clone();
    let target_folder_clone = target_folder.clone();
    let size_for_index = total_size;

    let file_uuid = tokio::task::spawn_blocking(move || {
        let uuid = crate::indexer::storage::create_pending_file(&target_folder_clone, None).ok()?;
        let path = Path::new(&file_path_clone);
        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_lowercase();
        let file_type = crate::indexer::scanner::classify_extension(&ext);
        match crate::indexer::storage::complete_pending_file(
            &uuid,
            &file_path_clone,
            &file_name_clone,
            &file_type,
            &ext,
            size_for_index as i64,
        ) {
            Ok(()) => Some(uuid),
            Err(e) => {
                eprintln!("[upload/chunk] index failed: {} - {}", file_path_clone, e);
                None
            }
        }
    })
    .await
    .unwrap_or(None);

    // 写入上传历史
    let history_item = storage::HistoryItem {
        id: upload_id.clone(),
        file_name: file_name.clone(),
        target_folder: target_folder.clone(),
        status: "completed".to_string(),
        file_size: total_size,
        file_uuid: file_uuid.clone(),
        error: None,
        created_at: session.created_at.clone(),
    };
    if let Err(e) = storage::add_to_history(history_item) {
        eprintln!("保存上传历史记录失败: {}", e);
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "upload_id": upload_id,
        "file_name": file_name,
        "file_size": total_size,
        "file_uuid": file_uuid,
        "message": "上传完成",
    })))
}

/// POST /api/transfer/upload/chunk/abort/{upload_id}
/// 取消上传并清理暂存分片
pub async fn abort_chunk_upload(
    path: web::Path<String>,
    manager: web::Data<ChunkUploadManager>,
) -> Result<HttpResponse> {
    let upload_id = path.into_inner();
    let stage_dir = stage_dir_for(&upload_id);
    let _ = tokio::fs::remove_dir_all(&stage_dir).await;
    manager.remove(&upload_id).await;
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "message": "已取消上传"
    })))
}
