// 文件内容服务功能（从classifier/handlers.rs迁移serve_file）
use actix_files::NamedFile;
use actix_web::{
    http::header::{ContentDisposition, DispositionType},
    web, HttpRequest, HttpResponse, Result,
};
use futures_util::stream;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::SystemTime;
use tokio::io::AsyncReadExt;

use super::models::CLIP_EXTENSION;
use super::utils::{extract_clip_thumbnail, get_ffmpeg_path};

/// 不被浏览器/AVPlayer 原生支持、需要转码播放的视频格式.
/// 这些格式会被改造成 "on-demand HLS": 服务端不写磁盘,
/// 每个 .ts 片段都是请求到达时临时 spawn ffmpeg 流式产出.
const HLS_TRANSCODE_EXTENSIONS: &[&str] = &["wmv", "flv", "avi", "mkv", "webm"];

/// 需要检查 faststart 的容器格式
const FASTSTART_CHECK_EXTENSIONS: &[&str] = &["mp4", "mov", "m4v"];

/// 可能包含 HEVC hev1 编码的容器格式（iOS AVPlayer 要求 hvc1 tag）
const HEVC_CHECK_EXTENSIONS: &[&str] = &["mp4", "mov", "m4v"];

/// 每个 HLS 切片的目标时长(秒).
/// 越小首帧越快、索引越长;6 秒是 Apple 推荐值的折中点.
const HLS_SEGMENT_SECONDS: f64 = 6.0;

// ============================================================================
// HLS: duration 缓存
// ============================================================================

/// 按 (path, mtime) 缓存 ffmpeg 探测到的视频时长,避免每次拉 m3u8 都 probe 一次.
/// mtime 变化自动作废缓存.
fn duration_cache() -> &'static Mutex<HashMap<PathBuf, (SystemTime, f64)>> {
    static CACHE: OnceLock<Mutex<HashMap<PathBuf, (SystemTime, f64)>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

/// 用 `ffmpeg -i` 的 stderr 解析 `Duration: HH:MM:SS.cs` 拿到时长.
fn probe_duration(file_path: &str, ffmpeg: &Path) -> Option<f64> {
    let output = std::process::Command::new(ffmpeg)
        .args(["-hide_banner", "-i", file_path])
        .output()
        .ok()?;
    let stderr = String::from_utf8_lossy(&output.stderr);
    let re = regex::Regex::new(r"Duration:\s*(\d+):(\d+):(\d+)\.(\d+)").ok()?;
    let caps = re.captures(&stderr)?;
    let h: f64 = caps[1].parse().ok()?;
    let m: f64 = caps[2].parse().ok()?;
    let s: f64 = caps[3].parse().ok()?;
    let cs: f64 = caps[4].parse().ok()?;
    Some(h * 3600.0 + m * 60.0 + s + cs / 100.0)
}

/// 取时长,命中内存缓存就立刻返回,未命中才调 probe_duration.
fn get_duration_cached(file_path: &Path) -> Option<f64> {
    let mtime = std::fs::metadata(file_path)
        .and_then(|m| m.modified())
        .ok()?;
    {
        let cache = duration_cache().lock().unwrap();
        if let Some((cached_mtime, d)) = cache.get(file_path) {
            if *cached_mtime == mtime {
                return Some(*d);
            }
        }
    }
    let ffmpeg = get_ffmpeg_path();
    let d = probe_duration(&file_path.to_string_lossy(), &ffmpeg)?;
    duration_cache()
        .lock()
        .unwrap()
        .insert(file_path.to_path_buf(), (mtime, d));
    Some(d)
}

/// 已知会触发探测失败的源文件黑名单,避免每次都去跑一次 ffmpeg 空跑.
/// (目前未使用,预留位置;probe 失败会直接返回 500 让客户端知道)
#[allow(dead_code)]
fn _probe_failure_registry() -> &'static Mutex<HashSet<PathBuf>> {
    static BL: OnceLock<Mutex<HashSet<PathBuf>>> = OnceLock::new();
    BL.get_or_init(|| Mutex::new(HashSet::new()))
}

// ============================================================================
// HLS: m3u8 生成
// ============================================================================

/// 构造一个 VOD 类型的 m3u8 playlist.
///
/// 每一条 segment URL 指回 `/api/preview/content/<encoded-src>?hls_seg=N&key=...`,
/// 这样播放器拉切片时:
/// 1. 走的是同一个 actix 路由,复用鉴权中间件
/// 2. URL 里带 `?key`,AVPlayer 不会因为丢 query string 而 401
fn build_m3u8(source_path: &Path, duration: f64, key: Option<&str>) -> String {
    use percent_encoding::{utf8_percent_encode, AsciiSet, CONTROLS, NON_ALPHANUMERIC};

    // 最小 query-value 转义集: 只转义真正会破坏 query string 结构的字符.
    // 保留 `_` `-` `.` 等 token 友好字符不编码, 因为 auth 中间件
    // (server/src/auth/middleware.rs) 对 `key=` 值是**不做 percent-decode**
    // 的直接字符串比对,过度编码会往返失配导致 401.
    const KEY_SET: &AsciiSet = &CONTROLS
        .add(b' ')
        .add(b'"')
        .add(b'#')
        .add(b'&')
        .add(b'+')
        .add(b'/')
        .add(b'=')
        .add(b'?');

    let encoded_src =
        utf8_percent_encode(&source_path.to_string_lossy(), NON_ALPHANUMERIC).to_string();
    let key_query = key
        .map(|k| format!("&key={}", utf8_percent_encode(k, KEY_SET)))
        .unwrap_or_default();

    let num_segs = (duration / HLS_SEGMENT_SECONDS).ceil() as usize;
    let target_dur = HLS_SEGMENT_SECONDS.ceil() as u32;

    let mut m3u8 = String::with_capacity(256 + num_segs * 96);
    m3u8.push_str("#EXTM3U\n");
    m3u8.push_str("#EXT-X-VERSION:3\n");
    m3u8.push_str(&format!("#EXT-X-TARGETDURATION:{}\n", target_dur));
    m3u8.push_str("#EXT-X-MEDIA-SEQUENCE:0\n");
    m3u8.push_str("#EXT-X-PLAYLIST-TYPE:VOD\n");
    m3u8.push_str("#EXT-X-INDEPENDENT-SEGMENTS\n");
    for i in 0..num_segs {
        let start = i as f64 * HLS_SEGMENT_SECONDS;
        let dur = (duration - start).min(HLS_SEGMENT_SECONDS);
        m3u8.push_str(&format!("#EXTINF:{:.3},\n", dur));
        // 注意: path 末尾拼一个 `.ts` 伪后缀. 真实播放器不在乎 URL 扩展名,
        // 但 ffmpeg 作为 HLS client 有一个 `allowed_extensions` 白名单,
        // 看到 `.wmv` 会拒绝. 拼 `.ts` 后所有客户端都能正确识别这是切片.
        // serve_file 开头会把 `.ts` 脱掉再按源文件处理.
        m3u8.push_str(&format!(
            "/api/preview/content/{}.ts?hls_seg={}{}\n",
            encoded_src, i, key_query
        ));
    }
    m3u8.push_str("#EXT-X-ENDLIST\n");
    m3u8
}

// ============================================================================
// HLS: on-demand segment 流式产出
// ============================================================================

/// 给单个切片临时 spawn 一次 ffmpeg,把 stdout 包装成 chunked HTTP body 返回.
///
/// 关键点:
/// - `-ss BEFORE -i` 快速定位(demuxer seek),自 ffmpeg 2.1 起也是帧准确的
/// - `-force_key_frames expr:gte(t,0)` 强制每段从 IDR 开头,段间可独立解码
/// - `-f mpegts` → 产出原始 .ts 字节流,HLS 标准切片格式
/// - `kill_on_drop(true)` → 客户端断开时顺带把 ffmpeg SIGKILL,避免僵尸
async fn serve_hls_segment(source_path: &Path, seg_idx: usize) -> Result<HttpResponse> {
    if !source_path.exists() {
        return Err(actix_web::error::ErrorNotFound("源文件不存在"));
    }

    let duration = get_duration_cached(source_path)
        .ok_or_else(|| actix_web::error::ErrorInternalServerError("无法探测视频时长"))?;

    let start = seg_idx as f64 * HLS_SEGMENT_SECONDS;
    if start >= duration {
        return Err(actix_web::error::ErrorNotFound("segment 超出范围"));
    }
    let seg_dur = (duration - start).min(HLS_SEGMENT_SECONDS);

    let ffmpeg = get_ffmpeg_path();
    let source_str = source_path
        .to_str()
        .ok_or_else(|| actix_web::error::ErrorInternalServerError("源路径含非 UTF-8"))?;

    let mut child = tokio::process::Command::new(&ffmpeg)
        .args([
            "-hide_banner",
            "-loglevel", "warning",
            // fast seek 到段起点 (在 -i 之前, demuxer seek, 很快)
            "-ss", &format!("{:.3}", start),
            "-i", source_str,
            "-t", &format!("{:.3}", seg_dur),
            // 视频: H.264 veryfast + crf 20.
            // ultrafast preset 会禁用 B 帧 / psy 优化 / in-loop deblocking, 画质肉眼可见地软;
            // veryfast 开回这些编码工具,同等视觉质量下码率反而更低,且 640x480 上仍有 >30x 实时速度.
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-crf", "20",
            "-pix_fmt", "yuv420p",
            // 强制段首为 IDR, 保证段间可独立解码
            "-force_key_frames", "expr:gte(t,0)",
            // 音频: AAC 128k stereo, 满足 Apple HLS 规范
            "-c:a", "aac",
            "-b:a", "128k",
            "-ac", "2",
            "-ar", "44100",
            // 输出: MPEG-TS 流到 stdout
            "-f", "mpegts",
            "-muxdelay", "0",
            "-muxpreload", "0",
            "pipe:1",
        ])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .map_err(|e| {
            actix_web::error::ErrorInternalServerError(format!("ffmpeg spawn 失败: {}", e))
        })?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| actix_web::error::ErrorInternalServerError("无法获取 ffmpeg stdout"))?;

    // 后台 drain stderr,既用于日志也防止 pipe 写满阻塞 ffmpeg
    if let Some(mut stderr) = child.stderr.take() {
        let src_display = source_path.display().to_string();
        tokio::spawn(async move {
            let mut buf = Vec::new();
            let _ = stderr.read_to_end(&mut buf).await;
            if !buf.is_empty() {
                let text = String::from_utf8_lossy(&buf);
                // warning+ 级别才打印, 减少噪音
                if text.contains("Error") || text.contains("error") {
                    eprintln!("[hls-seg {} idx={}] ffmpeg: {}", src_display, seg_idx, text);
                }
            }
        });
    }

    // 把 ffmpeg stdout 包装成 Stream<Bytes> 喂给 actix 的 streaming body.
    // unfold state 持有 child, 流结束/drop 时 child 跟着被 drop → kill_on_drop 触发.
    let state = (stdout, child, vec![0u8; 64 * 1024]);
    let body_stream = stream::unfold(state, |(mut stdout, mut child, mut buf)| async move {
        match stdout.read(&mut buf).await {
            Ok(0) => {
                // EOF: 等 child 退出,避免僵尸进程
                let _ = child.wait().await;
                None
            }
            Ok(n) => {
                let chunk = actix_web::web::Bytes::copy_from_slice(&buf[..n]);
                Some((
                    Ok::<_, std::io::Error>(chunk),
                    (stdout, child, buf),
                ))
            }
            Err(e) => {
                eprintln!("[hls-seg] stdout read 失败: {}", e);
                None
            }
        }
    });

    Ok(HttpResponse::Ok()
        .content_type("video/mp2t")
        .insert_header(("Cache-Control", "no-store"))
        .streaming(body_stream))
}

// ============================================================================
// 其他原有辅助: HEVC 探测 / faststart 检测
// ============================================================================

/// 检测视频文件是否为 HEVC hev1 编码。
/// iOS AVPlayer 只支持 hvc1 tag 的 HEVC，hev1 tag（ffmpeg/非 Apple 编码器默认）会黑屏。
fn is_hevc_hev1(file_path: &str, ffmpeg_path: &std::path::PathBuf) -> bool {
    let output = std::process::Command::new(ffmpeg_path)
        .args(["-hide_banner", "-i", file_path])
        .output();
    match output {
        Ok(o) => {
            let stderr = String::from_utf8_lossy(&o.stderr);
            let lower = stderr.to_lowercase();
            lower.contains("video: hevc") && lower.contains("(hev1")
        }
        Err(_) => false,
    }
}

/// Check if an MP4 file has moov atom before mdat (faststart).
/// Reads the file's top-level atoms sequentially. If mdat comes before moov, it's not faststart.
fn is_faststart(file_path: &Path) -> bool {
    use std::io::{Read, Seek, SeekFrom};
    let Ok(mut f) = std::fs::File::open(file_path) else { return true };
    let Ok(file_size) = f.seek(SeekFrom::End(0)) else { return true };
    let _ = f.seek(SeekFrom::Start(0));

    let mut pos: u64 = 0;
    let mut buf = [0u8; 8];
    while pos < file_size {
        if f.read_exact(&mut buf).is_err() { break }
        let size = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as u64;
        let atom_type = &buf[4..8];

        let atom_size = if size == 1 {
            let mut ext = [0u8; 8];
            if f.read_exact(&mut ext).is_err() { break }
            u64::from_be_bytes(ext)
        } else if size == 0 {
            file_size - pos
        } else {
            size
        };

        if atom_type == b"moov" { return true }
        if atom_type == b"mdat" { return false }

        if atom_size < 8 { break }
        pos += atom_size;
        let _ = f.seek(SeekFrom::Start(pos));
    }
    true
}

// ============================================================================
// 主入口: serve_file
// ============================================================================

/// GET /api/preview/content/{path:.*}
///
/// 统一的文件内容服务端点.
///
/// 一个请求可能走以下几种路径之一:
/// - `?uuid=<id>`           → 从 DB 查 current_path, 再走下面的文件逻辑
/// - `?hls_seg=<n>`         → 从源文件实时转出第 n 段 .ts (mpegts 字节流)
/// - 扩展名 ∈ CLIP          → 提取内嵌 PNG 预览图 (缓存到 .transcoded/)
/// - 扩展名 ∈ HLS_TRANSCODE → 返回 on-demand HLS playlist (m3u8 body, 不写磁盘)
/// - 扩展名 ∈ FASTSTART     → 若 MP4 缺 faststart, 缓存一个 remux 版本
/// - 扩展名 ∈ HEVC          → 若是 hev1, 重封装成 hvc1 (iOS 兼容)
/// - 其他                   → 原样走 NamedFile 静态文件服务 (Range / ETag / MIME 自动)
pub async fn serve_file(
    path: web::Path<String>,
    query: web::Query<HashMap<String, String>>,
    req: HttpRequest,
) -> Result<HttpResponse> {
    // 1. 解析源文件路径 (UUID 或 URL path)
    let file_path = if let Some(uuid) = query.get("uuid") {
        let file = crate::indexer::storage::get_file_by_uuid(uuid)
            .map_err(|e| actix_web::error::ErrorInternalServerError(format!("数据库错误: {}", e)))?
            .ok_or_else(|| actix_web::error::ErrorNotFound("UUID 对应的文件未找到"))?;
        file.current_path
            .ok_or_else(|| actix_web::error::ErrorNotFound("文件已被删除或移动"))?
    } else {
        percent_encoding::percent_decode_str(&path)
            .decode_utf8_lossy()
            .to_string()
    };

    // 2. HLS segment 请求: 优先匹配, 不再走任何其它分支.
    //    段 URL 形态: `/api/preview/content/<encoded-src>.ts?hls_seg=N&key=...`
    //    这里需要先脱掉 `.ts` 伪后缀, 拿到真实源文件路径.
    if let Some(seg_str) = query.get("hls_seg") {
        let seg_idx: usize = seg_str
            .parse()
            .map_err(|_| actix_web::error::ErrorBadRequest("hls_seg 必须是非负整数"))?;
        let real_src = file_path
            .strip_suffix(".ts")
            .unwrap_or(&file_path);
        return serve_hls_segment(Path::new(real_src), seg_idx).await;
    }

    let source_path = Path::new(&file_path);

    // 3. 提取扩展名
    let extension = source_path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();

    // 4. .clip 文件: 提取内嵌 PNG 预览图 (缓存到 .transcoded/)
    if extension == CLIP_EXTENSION && source_path.exists() {
        let parent = source_path
            .parent()
            .ok_or_else(|| actix_web::error::ErrorInternalServerError("无法获取文件所在目录"))?;
        let transcode_dir = parent.join(".transcoded");
        let stem = source_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("output");
        let cache_path = transcode_dir.join(format!("{}.png", stem));

        if cache_path.exists() {
            let src_modified = std::fs::metadata(source_path).and_then(|m| m.modified()).ok();
            let cache_modified = std::fs::metadata(&cache_path).and_then(|m| m.modified()).ok();
            if let (Some(src_t), Some(cache_t)) = (src_modified, cache_modified) {
                if cache_t >= src_t {
                    return named_file_response(&cache_path.to_string_lossy(), &req).await;
                }
            }
        }

        std::fs::create_dir_all(&transcode_dir).map_err(|e| {
            actix_web::error::ErrorInternalServerError(format!("无法创建转码目录: {}", e))
        })?;

        let img = extract_clip_thumbnail(source_path)?;
        img.save_with_format(&cache_path, image::ImageFormat::Png)
            .map_err(|e| {
                actix_web::error::ErrorInternalServerError(format!("无法保存 CLIP 预览图: {}", e))
            })?;

        return named_file_response(&cache_path.to_string_lossy(), &req).await;
    }

    // 5. HLS 转码格式 (wmv/flv/avi/mkv/webm): 返回 on-demand m3u8 playlist
    if HLS_TRANSCODE_EXTENSIONS.contains(&extension.as_str()) && source_path.exists() {
        let duration = get_duration_cached(source_path).ok_or_else(|| {
            actix_web::error::ErrorInternalServerError("ffmpeg 无法探测视频时长")
        })?;
        let m3u8 = build_m3u8(source_path, duration, query.get("key").map(|s| s.as_str()));
        return Ok(HttpResponse::Ok()
            .content_type("application/vnd.apple.mpegurl")
            .insert_header(("Cache-Control", "no-store"))
            .body(m3u8));
    }

    // 6. MP4 faststart 检测: 若 moov 在 mdat 之后, 缓存一个 remux 过的版本
    if FASTSTART_CHECK_EXTENSIONS.contains(&extension.as_str())
        && source_path.exists()
        && !is_faststart(source_path)
    {
        let parent = source_path
            .parent()
            .ok_or_else(|| actix_web::error::ErrorInternalServerError("无法获取文件所在目录"))?;
        let transcode_dir = parent.join(".transcoded");
        let stem = source_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("output");
        let cache_path = transcode_dir.join(format!("{}_faststart.mp4", stem));

        if cache_path.exists() {
            let src_modified = std::fs::metadata(source_path).and_then(|m| m.modified()).ok();
            let cache_modified = std::fs::metadata(&cache_path).and_then(|m| m.modified()).ok();
            if let (Some(src_t), Some(cache_t)) = (src_modified, cache_modified) {
                if cache_t >= src_t {
                    return named_file_response(&cache_path.to_string_lossy(), &req).await;
                }
            }
        }

        std::fs::create_dir_all(&transcode_dir).map_err(|e| {
            actix_web::error::ErrorInternalServerError(format!("无法创建转码目录: {}", e))
        })?;

        let ffmpeg_path = get_ffmpeg_path();
        let cache_path_str = cache_path.to_str().ok_or_else(|| {
            actix_web::error::ErrorInternalServerError("缓存路径含非 UTF-8 字符")
        })?;

        eprintln!("[faststart] remuxing: {}", source_path.display());
        let output = std::process::Command::new(&ffmpeg_path)
            .args([
                "-i", &file_path, "-c", "copy", "-movflags", "+faststart", "-y", cache_path_str,
            ])
            .output()
            .map_err(|e| {
                actix_web::error::ErrorInternalServerError(format!("ffmpeg faststart 失败: {}", e))
            })?;

        if output.status.success() {
            return named_file_response(&cache_path.to_string_lossy(), &req).await;
        } else {
            let _ = std::fs::remove_file(&cache_path);
            // 降级: 走下面的原文件路径
        }
    }

    // 7. HEVC hev1 → hvc1 重封装 (iOS AVPlayer 兼容)
    if HEVC_CHECK_EXTENSIONS.contains(&extension.as_str()) && source_path.exists() {
        let parent = source_path
            .parent()
            .ok_or_else(|| actix_web::error::ErrorInternalServerError("无法获取文件所在目录"))?;
        let transcode_dir = parent.join(".transcoded");
        let stem = source_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("output");
        let cache_path = transcode_dir.join(format!("{}_hvc1.mp4", stem));
        let skip_marker = transcode_dir.join(format!("{}.not_hev1", stem));

        let src_modified = std::fs::metadata(source_path).and_then(|m| m.modified()).ok();

        if cache_path.exists() {
            let cache_modified = std::fs::metadata(&cache_path).and_then(|m| m.modified()).ok();
            if let (Some(src_t), Some(cache_t)) = (src_modified, cache_modified) {
                if cache_t >= src_t {
                    return named_file_response(&cache_path.to_string_lossy(), &req).await;
                }
            }
        }

        if skip_marker.exists() {
            let marker_modified = std::fs::metadata(&skip_marker).and_then(|m| m.modified()).ok();
            if let (Some(src_t), Some(marker_t)) = (src_modified, marker_modified) {
                if marker_t >= src_t {
                    return named_file_response(&file_path, &req).await;
                }
            }
        }

        let ffmpeg_path = get_ffmpeg_path();
        if is_hevc_hev1(&file_path, &ffmpeg_path) {
            std::fs::create_dir_all(&transcode_dir).map_err(|e| {
                actix_web::error::ErrorInternalServerError(format!("无法创建转码目录: {}", e))
            })?;

            let cache_path_str = cache_path.to_str().ok_or_else(|| {
                actix_web::error::ErrorInternalServerError("缓存路径含非 UTF-8 字符")
            })?;
            let output = std::process::Command::new(&ffmpeg_path)
                .args([
                    "-i", &file_path,
                    "-c", "copy",
                    "-tag:v", "hvc1",
                    "-movflags", "+faststart",
                    "-y",
                    cache_path_str,
                ])
                .output()
                .map_err(|e| {
                    actix_web::error::ErrorInternalServerError(format!("ffmpeg 重封装失败: {}", e))
                })?;

            if output.status.success() {
                return named_file_response(&cache_path.to_string_lossy(), &req).await;
            } else {
                let _ = std::fs::remove_file(&cache_path);
            }
        } else {
            let _ = std::fs::create_dir_all(&transcode_dir);
            let _ = std::fs::write(&skip_marker, b"");
        }
    }

    // 8. 兜底: 原样 NamedFile (含 Range / ETag / MIME)
    named_file_response(&file_path, &req).await
}

/// 把指定路径封装成 NamedFile,再转成支持 Range 的 HttpResponse 返回.
async fn named_file_response(path: &str, req: &HttpRequest) -> Result<HttpResponse> {
    let mut f = NamedFile::open_async(path)
        .await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("打开文件失败: {}", e)))?;
    f = f.set_content_disposition(ContentDisposition {
        disposition: DispositionType::Inline,
        parameters: vec![],
    });
    Ok(f.into_response(req))
}
