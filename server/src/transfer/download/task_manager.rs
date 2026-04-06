// 任务管理器：管理下载任务队列、状态追踪、进度更新
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use super::models::{DownloadTask, Platform, DownloaderType, TaskStatus};
use super::storage;

/// 任务管理器
pub struct TaskManager {
    tasks: Arc<Mutex<HashMap<String, DownloadTask>>>,
}

impl TaskManager {
    /// 创建新的任务管理器
    pub fn new() -> Self {
        TaskManager {
            tasks: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// 创建新任务并开始下载
    pub async fn create_task(
        &self,
        url: String,
        platform: Platform,
        downloader: DownloaderType,
        save_folder: String,
        format: Option<String>,
    ) -> Result<String, String> {
        // 1. 生成唯一任务 ID
        let task_id = uuid::Uuid::new_v4().to_string();

        // 2. 创建任务对象
        let task = DownloadTask {
            id: task_id.clone(),
            url: url.clone(),
            platform: platform.clone(),
            downloader: downloader.clone(),
            status: TaskStatus::Pending,
            progress: 0.0,
            speed: None,
            eta: None,
            save_folder: save_folder.clone(),
            file_name: None,
            file_path: None,
            file_uuid: None,
            error: None,
            created_at: chrono::Utc::now().to_rfc3339(),
        };

        // 3. 存储任务
        self.tasks.lock().await.insert(task_id.clone(), task);

        // 4. 异步启动下载
        let task_id_clone = task_id.clone();
        let tasks_clone = self.tasks.clone();
        tokio::spawn(async move {
            Self::execute_download(
                task_id_clone,
                url,
                platform,
                downloader,
                save_folder,
                format,
                tasks_clone,
            )
            .await;
        });

        Ok(task_id)
    }

    /// 获取单个任务
    pub async fn get_task(&self, task_id: &str) -> Option<DownloadTask> {
        self.tasks.lock().await.get(task_id).cloned()
    }

    /// 获取所有任务
    pub async fn get_all_tasks(&self) -> Vec<DownloadTask> {
        self.tasks.lock().await.values().cloned().collect()
    }

    /// 取消任务并移入历史记录
    pub async fn cancel_task(&self, task_id: &str) -> Result<(), String> {
        let mut tasks = self.tasks.lock().await;

        if let Some(task) = tasks.get(task_id) {
            // 只有 Pending 或 Downloading 状态才能取消
            match task.status {
                TaskStatus::Pending | TaskStatus::Downloading => {
                    // 移除任务并添加到历史记录
                    if let Some(task) = tasks.remove(task_id) {
                        let history_item = storage::HistoryItem {
                            id: task.id.clone(),
                            url: task.url.clone(),
                            platform: task.platform.to_string(),
                            status: "cancelled".to_string(),
                            file_name: None,
                            file_path: None,
                            file_uuid: None,
                            error: None,
                            created_at: task.created_at.clone(),
                        };

                        if let Err(e) = storage::add_to_history(history_item) {
                            eprintln!("保存历史记录失败: {}", e);
                        }
                    }
                    Ok(())
                }
                _ => Err("任务已完成或已取消，无法再次取消".to_string()),
            }
        } else {
            Err("任务不存在".to_string())
        }
    }

    /// 执行下载（私有函数）
    async fn execute_download(
        task_id: String,
        url: String,
        platform: Platform,
        downloader: DownloaderType,
        save_folder: String,
        format: Option<String>,
        tasks: Arc<Mutex<HashMap<String, DownloadTask>>>,
    ) {
        // 1. 更新状态为 Downloading
        if let Some(task) = tasks.lock().await.get_mut(&task_id) {
            task.status = TaskStatus::Downloading;
        }

        // 2. Pre-register file in database → get UUID + save source_url
        let file_uuid = tokio::task::spawn_blocking({
            let save_folder = save_folder.clone();
            let url = url.clone();
            move || {
                match crate::indexer::storage::create_pending_file(&save_folder, Some(&url)) {
                    Ok(uuid) => {
                        eprintln!("[download] pre-registered: uuid={} folder={} url={}", uuid, save_folder, url);
                        Some(uuid)
                    }
                    Err(e) => {
                        eprintln!("[download] pre-register failed: folder={} error={}", save_folder, e);
                        None
                    }
                }
            }
        }).await.unwrap_or(None);

        // Store UUID in task
        if let Some(ref uuid) = file_uuid {
            if let Some(task) = tasks.lock().await.get_mut(&task_id) {
                task.file_uuid = Some(uuid.clone());
            }
        }

        // 3. 根据下载器类型调用对应的下载器
        let result = match downloader {
            DownloaderType::YtDlp => {
                let task_id_clone = task_id.clone();
                let tasks_clone = tasks.clone();

                super::downloaders::ytdlp::download(
                    url.clone(),
                    platform,
                    save_folder.clone(),
                    format,
                    file_uuid.clone(),
                    move |progress, speed, eta| {
                        let task_id = task_id_clone.clone();
                        let tasks = tasks_clone.clone();

                        // 在回调中更新进度
                        tokio::spawn(async move {
                            if let Some(task) = tasks.lock().await.get_mut(&task_id) {
                                task.progress = progress;
                                task.speed = speed;
                                task.eta = eta;
                            }
                        });
                    },
                )
                .await
            }
            DownloaderType::PixivToolkit => {
                // 1. 获取 Pixiv token
                match super::auth::pixiv::load_token() {
                    Ok(token) => {
                        // 2. 解析 URL 并获取作品信息
                        match super::downloaders::pixiv_toolkit::parser::PixivParser::parse_url(&url) {
                            Ok(parser) => {
                                match parser.fetch_illust_info(&token).await {
                                    Ok(illust_meta) => {
                                        // 3. 根据作品类型选择下载方式
                                        if illust_meta.illust_type == 2 {
                                            // 动图：下载 ZIP + 转换 GIF
                                            let task_id_clone = task_id.clone();
                                            let tasks_clone = tasks.clone();

                                            match super::downloaders::pixiv_toolkit::download_ugoira_zip(
                                                url.clone(),
                                                token.clone(),
                                                save_folder.clone(),
                                            )
                                            .await
                                            {
                                                Ok((zip_path, meta)) => {
                                                    // 更新进度到 50%
                                                    if let Some(task) = tasks_clone.lock().await.get_mut(&task_id_clone) {
                                                        task.progress = 50.0;
                                                    }

                                                    // 转换为 GIF
                                                    match super::downloaders::pixiv_toolkit::convert_ugoira_to_gif(
                                                        zip_path.clone(),
                                                        meta,
                                                        save_folder.clone(),
                                                        parser.illust_id.clone(),
                                                        move |progress| {
                                                            let task_id = task_id_clone.clone();
                                                            let tasks = tasks_clone.clone();

                                                            tokio::spawn(async move {
                                                                if let Some(task) = tasks.lock().await.get_mut(&task_id) {
                                                                    task.progress = 50.0 + progress * 50.0;
                                                                }
                                                            });
                                                        },
                                                    )
                                                    .await
                                                    {
                                                        Ok(gif_path) => Ok(gif_path),
                                                        Err(e) => Err(format!("GIF 转换失败: {}", e)),
                                                    }
                                                }
                                                Err(e) => Err(format!("ZIP 下载失败: {}", e)),
                                            }
                                        } else {
                                            // 普通图片/漫画：下载所有页面
                                            let task_id_clone = task_id.clone();
                                            let tasks_clone = tasks.clone();

                                            match super::downloaders::pixiv_toolkit::download_illust(
                                                url.clone(),
                                                token,
                                                save_folder.clone(),
                                                move |current, total| {
                                                    let task_id = task_id_clone.clone();
                                                    let tasks = tasks_clone.clone();

                                                    tokio::spawn(async move {
                                                        if let Some(task) = tasks.lock().await.get_mut(&task_id) {
                                                            task.progress = (current as f32 / total as f32) * 100.0;
                                                        }
                                                    });
                                                },
                                            )
                                            .await
                                            {
                                                Ok(files) => {
                                                    files.last().cloned().ok_or_else(|| "没有下载任何文件".to_string())
                                                }
                                                Err(e) => Err(format!("图片下载失败: {}", e)),
                                            }
                                        }
                                    }
                                    Err(e) => Err(format!("获取作品信息失败: {}", e)),
                                }
                            }
                            Err(e) => Err(format!("URL 解析失败: {}", e)),
                        }
                    }
                    Err(e) => Err(format!("Pixiv 需要认证，请先上传 PHPSESSID token: {}", e)),
                }
            }
            _ => Err("不支持的下载器类型".to_string()),
        };

        // 3. 根据结果更新任务状态，并立即移入历史记录
        let task_info = tasks.lock().await.remove(&task_id);

        if let Some(task) = task_info {
            match result {
                Ok(file_path) => {
                    // 下载成功
                    let file_name = std::path::Path::new(&file_path)
                        .file_name()
                        .and_then(|n| n.to_str())
                        .unwrap_or("unknown")
                        .to_string();

                    // 标准化文件路径
                    let file_path = std::path::Path::new(&file_path)
                        .canonicalize()
                        .map(|p| p.to_string_lossy().to_string())
                        .unwrap_or(file_path);

                    // 更新预注册的文件记录（填入实际路径和元数据）
                    let file_path_clone = file_path.clone();
                    let file_name_clone = file_name.clone();
                    let file_uuid_clone = file_uuid.clone();
                    tokio::task::spawn_blocking(move || {
                        if let Some(ref uuid) = file_uuid_clone {
                            let path = std::path::Path::new(&file_path_clone);
                            let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
                            let file_type = crate::indexer::scanner::classify_extension(&ext);
                            let file_size = std::fs::metadata(&file_path_clone).map(|m| m.len() as i64).unwrap_or(0);
                            match crate::indexer::storage::complete_pending_file(uuid, &file_path_clone, &file_name_clone, &file_type, &ext, file_size) {
                                Ok(()) => eprintln!("[download] completed: {} uuid={}", file_path_clone, uuid),
                                Err(e) => eprintln!("[download] complete_pending failed: {} - {}", uuid, e),
                            }
                        }
                    }).await.ok();

                    // 添加到历史记录（携带 file_uuid）
                    let history_item = storage::HistoryItem {
                        id: task.id.clone(),
                        url: task.url.clone(),
                        platform: task.platform.to_string(),
                        status: "completed".to_string(),
                        file_name: Some(file_name),
                        file_path: Some(file_path.clone()),
                        file_uuid,
                        error: None,
                        created_at: task.created_at.clone(),
                    };

                    if let Err(e) = storage::add_to_history(history_item) {
                        eprintln!("保存历史记录失败: {}", e);
                    }
                }
                Err(error) => {
                    // 下载失败 — 删除预注册的占位记录
                    if let Some(ref uuid) = file_uuid {
                        let uuid_clone = uuid.clone();
                        let _ = tokio::task::spawn_blocking(move || {
                            if let Err(e) = crate::indexer::storage::delete_pending_file(&uuid_clone) {
                                eprintln!("[download] cleanup pending failed: {}", e);
                            }
                        }).await;
                    }

                    let history_item = storage::HistoryItem {
                        id: task.id.clone(),
                        url: task.url.clone(),
                        platform: task.platform.to_string(),
                        status: "failed".to_string(),
                        file_name: None,
                        file_path: None,
                        file_uuid: None,
                        error: Some(error),
                        created_at: task.created_at.clone(),
                    };

                    if let Err(e) = storage::add_to_history(history_item) {
                        eprintln!("保存历史记录失败: {}", e);
                    }
                }
            }
        }
    }
}

impl Default for TaskManager {
    fn default() -> Self {
        Self::new()
    }
}
