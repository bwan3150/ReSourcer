// FFmpeg等工具函数（从gallery/handlers.rs迁移）
use std::path::{Path, PathBuf};
use std::fs;
use actix_web::Result;
use std::process::Command;

/// 获取 tools/ 目录路径（基于 app_dir，与部署目录一致）
fn tools_dir() -> PathBuf {
    crate::static_files::tools_dir()
}

/// 确保 tools/ 下的外部二进制存在（缺失则按配置 URL 下载）
fn ensure_tool_binary(name: &str) -> PathBuf {
    let binary_name = crate::tools::tool_binary_name(name);
    let binary_path = tools_dir().join(&binary_name);

    if binary_path.exists() {
        return binary_path;
    }

    let download_url = crate::tools::get_tool_download_url(name)
        .unwrap_or_else(|| panic!("未找到 {} 下载源配置", name));

    eprintln!("[{}] 未找到 {}，正在下载...", name, name);
    eprintln!("[{}] URL: {}", name, download_url);

    let dir = binary_path.parent().unwrap();
    fs::create_dir_all(dir).unwrap_or_else(|_| panic!("无法创建 tools 目录"));

    let output = std::process::Command::new("curl")
        .args(["-sSL", "-o", binary_path.to_str().unwrap(), &download_url])
        .output()
        .unwrap_or_else(|_| panic!("无法执行 curl 下载 {}", name));

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        panic!("下载 {} 失败: {}", name, stderr);
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&binary_path)
            .unwrap_or_else(|_| panic!("无法读取 {} 元数据", name))
            .permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&binary_path, perms)
            .unwrap_or_else(|_| panic!("无法设置 {} 可执行权限", name));
    }

    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("xattr")
            .args(["-cr", binary_path.to_str().unwrap()])
            .output();
    }

    eprintln!("[{}] 下载完成: {}", name, binary_path.display());
    binary_path
}

/// 获取 ffmpeg 二进制文件路径（从 tools/ 目录查找，不存在则从配置的 URL 下载）
pub fn get_ffmpeg_path() -> PathBuf {
    ensure_tool_binary("ffmpeg")
}

/// 获取 ffprobe 二进制文件路径
pub fn get_ffprobe_path() -> PathBuf {
    ensure_tool_binary("ffprobe")
}

/// HEIF tile grid 中的单个 tile
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HeifTile {
    pub stream_index: usize,
    pub x: u32,
    pub y: u32,
}

/// HEIF tile grid（iPhone 等高分辨率 HEIC 常用）
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HeifTileGrid {
    /// tile 拼合后的编码画布尺寸（常为 tile 对齐后的 padded 尺寸）
    pub coded_width: u32,
    pub coded_height: u32,
    /// 实际可见/显示区域（ispe），可能小于 coded_*；无标记时等于 coded_*
    pub display_width: u32,
    pub display_height: u32,
    /// 显示区域相对编码画布的偏移（horizontal_offset / vertical_offset）
    pub crop_x: u32,
    pub crop_y: u32,
    pub tiles: Vec<HeifTile>,
}

impl HeifTileGrid {
    /// 编码画布大于显示区域时需要 crop，否则 xstack 会留下黑边，
    /// 再叠加 Orientation 旋转后表现为大图「左空右切」。
    pub fn needs_display_crop(&self) -> bool {
        self.display_width > 0
            && self.display_height > 0
            && (self.display_width < self.coded_width
                || self.display_height < self.coded_height
                || self.crop_x > 0
                || self.crop_y > 0)
    }
}

/// 解析 `ffprobe -show_stream_groups` 输出中的 Tile Grid。
/// 若文件不含拼贴网格（或只有 1 个 tile），返回 None。
pub fn parse_heif_tile_grid(probe_output: &str) -> Option<HeifTileGrid> {
    let mut best: Option<HeifTileGrid> = None;

    let mut in_group = false;
    let mut group_is_tile = false;
    let mut in_component = false;
    let mut coded_width: u32 = 0;
    let mut coded_height: u32 = 0;
    let mut display_width: u32 = 0;
    let mut display_height: u32 = 0;
    let mut crop_x: u32 = 0;
    let mut crop_y: u32 = 0;
    let mut tiles: Vec<HeifTile> = Vec::new();

    let mut in_sub = false;
    let mut sub_stream: Option<usize> = None;
    let mut sub_x: u32 = 0;
    let mut sub_y: u32 = 0;

    for line in probe_output.lines() {
        let line = line.trim();
        match line {
            "[STREAM_GROUP]" => {
                in_group = true;
                group_is_tile = false;
                in_component = false;
                coded_width = 0;
                coded_height = 0;
                display_width = 0;
                display_height = 0;
                crop_x = 0;
                crop_y = 0;
                tiles.clear();
            }
            "[/STREAM_GROUP]" => {
                if in_group && group_is_tile && tiles.len() > 1 {
                    tiles.sort_by_key(|t| t.stream_index);
                    // 无 width/height 时退回 coded 尺寸（无 padding）
                    let dw = if display_width > 0 {
                        display_width
                    } else {
                        coded_width
                    };
                    let dh = if display_height > 0 {
                        display_height
                    } else {
                        coded_height
                    };
                    let candidate = HeifTileGrid {
                        coded_width,
                        coded_height,
                        display_width: dw,
                        display_height: dh,
                        crop_x,
                        crop_y,
                        tiles: tiles.clone(),
                    };
                    let replace = match &best {
                        None => true,
                        Some(prev) => {
                            candidate.coded_width * candidate.coded_height
                                > prev.coded_width * prev.coded_height
                        }
                    };
                    if replace {
                        best = Some(candidate);
                    }
                }
                in_group = false;
                group_is_tile = false;
                in_component = false;
            }
            "[COMPONENT]" if in_group => {
                in_component = true;
            }
            "[/COMPONENT]" => {
                in_component = false;
            }
            "[SUBCOMPONENT]" => {
                in_sub = true;
                sub_stream = None;
                sub_x = 0;
                sub_y = 0;
            }
            "[/SUBCOMPONENT]" => {
                if in_sub {
                    if let Some(idx) = sub_stream {
                        tiles.push(HeifTile {
                            stream_index: idx,
                            x: sub_x,
                            y: sub_y,
                        });
                    }
                }
                in_sub = false;
            }
            _ if in_group => {
                if let Some(rest) = line.strip_prefix("type=") {
                    group_is_tile = rest == "Tile Grid";
                } else if in_component && !in_sub {
                    // 只读 COMPONENT 级尺寸；STREAM 内 width/coded_width=512 会污染 pad 检测
                    if let Some(rest) = line.strip_prefix("coded_width=") {
                        if let Ok(v) = rest.parse() {
                            coded_width = v;
                        }
                    } else if let Some(rest) = line.strip_prefix("coded_height=") {
                        if let Ok(v) = rest.parse() {
                            coded_height = v;
                        }
                    } else if let Some(rest) = line.strip_prefix("width=") {
                        if let Ok(v) = rest.parse::<u32>() {
                            display_width = v;
                        }
                    } else if let Some(rest) = line.strip_prefix("height=") {
                        if let Ok(v) = rest.parse::<u32>() {
                            display_height = v;
                        }
                    } else if let Some(rest) = line.strip_prefix("horizontal_offset=") {
                        if let Ok(v) = rest.parse() {
                            crop_x = v;
                        }
                    } else if let Some(rest) = line.strip_prefix("vertical_offset=") {
                        if let Ok(v) = rest.parse() {
                            crop_y = v;
                        }
                    }
                } else if in_sub {
                    if let Some(rest) = line.strip_prefix("stream_index=") {
                        sub_stream = rest.parse().ok();
                    } else if let Some(rest) = line.strip_prefix("tile_horizontal_offset=") {
                        if let Ok(v) = rest.parse() {
                            sub_x = v;
                        }
                    } else if let Some(rest) = line.strip_prefix("tile_vertical_offset=") {
                        if let Ok(v) = rest.parse() {
                            sub_y = v;
                        }
                    }
                }
            }
            _ => {}
        }
    }

    best
}

/// 用 ffprobe 探测 HEIF/AVIF 是否为 tile grid
pub fn probe_heif_tile_grid(image_path: &Path) -> Option<HeifTileGrid> {
    let path_str = image_path.to_str()?;
    let ffprobe = get_ffprobe_path();
    let output = Command::new(&ffprobe)
        .args([
            "-v",
            "error",
            "-show_stream_groups",
            "-show_streams",
            path_str,
        ])
        .output()
        .ok()?;
    if !output.status.success() && output.stdout.is_empty() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    parse_heif_tile_grid(&text)
}

/// 构建 xstack layout 字符串（绝对偏移，适配不规则网格）
pub fn build_xstack_layout(tiles: &[HeifTile]) -> String {
    tiles
        .iter()
        .map(|t| format!("{}_{}", t.x, t.y))
        .collect::<Vec<_>>()
        .join("|")
}

/// HEIC/HEIF/AVIF 缩略图：若为 tile grid 则先拼合再缩放，避免只输出单块 tile
pub fn extract_heif_thumbnail(image_path: &Path, max_size: u32) -> Result<image::DynamicImage> {
    if let Some(grid) = probe_heif_tile_grid(image_path) {
        eprintln!(
            "[thumbnail] HEIF tile grid coded={}x{} display={}x{}+{}+{} ({} tiles) → 拼合解码 ({:?})",
            grid.coded_width,
            grid.coded_height,
            grid.display_width,
            grid.display_height,
            grid.crop_x,
            grid.crop_y,
            grid.tiles.len(),
            image_path
        );
        return extract_heif_tiled_thumbnail(image_path, &grid, max_size);
    }
    extract_image_thumbnail_ffmpeg(image_path, max_size)
}

/// 用 ffmpeg xstack 按探测到的偏移拼合 tile，裁掉 coded padding，再缩放到目标尺寸
fn extract_heif_tiled_thumbnail(
    image_path: &Path,
    grid: &HeifTileGrid,
    max_size: u32,
) -> Result<image::DynamicImage> {
    let ffmpeg_path = get_ffmpeg_path();
    let temp_output = std::env::temp_dir().join(format!("heif_{}.jpg", uuid::Uuid::new_v4()));
    let path_str = image_path
        .to_str()
        .ok_or_else(|| actix_web::error::ErrorBadRequest("无效的文件路径"))?;

    let inputs: String = grid
        .tiles
        .iter()
        .map(|t| format!("[0:{}]", t.stream_index))
        .collect();
    let layout = build_xstack_layout(&grid.tiles);
    let mut filter = format!(
        "{}xstack=inputs={}:layout={}",
        inputs,
        grid.tiles.len(),
        layout
    );
    // HEIF tile 对齐常把画布 pad 到 tile 边界（如 1200x900 → 1536x1024）。
    // 若不 crop 到 ispe 显示区，黑边会在 Orientation 旋转后变成「左空右切」。
    if grid.needs_display_crop() {
        filter.push_str(&format!(
            ",crop={}:{}:{}:{}",
            grid.display_width, grid.display_height, grid.crop_x, grid.crop_y
        ));
    }
    if max_size > 0 {
        filter.push_str(&format!(
            ",scale={}:{}:force_original_aspect_ratio=decrease",
            max_size, max_size
        ));
    }

    let output = Command::new(&ffmpeg_path)
        .args([
            "-i",
            path_str,
            "-filter_complex",
            &filter,
            "-frames:v",
            "1",
            "-update",
            "1",
            "-q:v",
            "2",
            "-y",
            temp_output.to_str().unwrap(),
        ])
        .output()
        .map_err(|e| {
            actix_web::error::ErrorInternalServerError(format!("FFmpeg 执行失败: {}", e))
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let _ = fs::remove_file(&temp_output);
        return Err(actix_web::error::ErrorInternalServerError(format!(
            "FFmpeg HEIF tile 拼合失败: {}",
            stderr
        )));
    }

    let img = image::open(&temp_output).map_err(|e| {
        let _ = fs::remove_file(&temp_output);
        actix_web::error::ErrorInternalServerError(format!("无法读取拼合后的图片: {}", e))
    })?;
    let _ = fs::remove_file(&temp_output);
    Ok(img)
}

/// 从视频提取首帧
pub fn extract_video_first_frame(video_path: &Path) -> Result<image::DynamicImage> {
    // 获取内嵌的 ffmpeg 路径
    let ffmpeg_path = get_ffmpeg_path();

    // 创建临时文件保存首帧
    let temp_output = std::env::temp_dir().join(format!("thumb_{}.jpg", uuid::Uuid::new_v4()));

    // 使用 ffmpeg 提取第一帧
    // -i: 输入文件
    // -vf "select=eq(n\,0)": 选择第一帧
    // -vframes 1: 只输出1帧
    // -q:v 2: 高质量输出
    let output = Command::new(&ffmpeg_path)
        .args(&[
            "-i", video_path.to_str().unwrap(),
            "-vf", "select=eq(n\\,0)",
            "-vframes", "1",
            "-q:v", "2",
            "-y", // 覆盖已存在的文件
            temp_output.to_str().unwrap(),
        ])
        .output()
        .map_err(|e| {
            actix_web::error::ErrorInternalServerError(
                format!("FFmpeg 执行失败 (请确保已安装 ffmpeg): {}", e)
            )
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        // 清理临时文件
        let _ = fs::remove_file(&temp_output);
        return Err(actix_web::error::ErrorInternalServerError(
            format!("FFmpeg 提取首帧失败: {}", stderr)
        ));
    }

    // 读取生成的首帧图片
    let img = image::open(&temp_output)
        .map_err(|e| {
            let _ = fs::remove_file(&temp_output);
            actix_web::error::ErrorInternalServerError(format!("无法读取视频首帧: {}", e))
        })?;

    // 清理临时文件
    let _ = fs::remove_file(&temp_output);

    Ok(img)
}

/// 使用 ffmpeg 提取音频文件的嵌入封面图（专辑封面）
/// 如果音频文件没有嵌入封面，返回 None
pub fn extract_audio_cover(audio_path: &Path) -> Option<image::DynamicImage> {
    let ffmpeg_path = get_ffmpeg_path();
    let temp_output = std::env::temp_dir().join(format!("cover_{}.jpg", uuid::Uuid::new_v4()));

    // ffmpeg -i input.mp3 -an -vcodec mjpeg -vframes 1 output.jpg
    let output = Command::new(&ffmpeg_path)
        .args(&[
            "-i", audio_path.to_str()?,
            "-an",
            "-vcodec", "mjpeg",
            "-vframes", "1",
            "-y",
            temp_output.to_str()?,
        ])
        .output()
        .ok()?;

    if !output.status.success() {
        let _ = fs::remove_file(&temp_output);
        return None;
    }

    let img = image::open(&temp_output).ok();
    let _ = fs::remove_file(&temp_output);
    img
}

/// 使用 ffmpeg 将图片（HEIC/AVIF 等 image 库不支持的格式）转为 JPEG 后读取
#[allow(dead_code)]
pub fn extract_image_frame_ffmpeg(image_path: &Path) -> Result<image::DynamicImage> {
    extract_image_thumbnail_ffmpeg(image_path, 0)
}

/// 用 ffmpeg 将图片直接缩放到目标尺寸后读取
/// max_size=0 表示不缩放（保留原始分辨率）
/// 用于 image::open 内存超限时的 fallback，避免把超大图完整载入内存
///
/// 缩放走 `-filter_complex` 而非 `-vf`：新版 ffmpeg（含仓库 macos 构建）对 HEIF
/// tile grid 会自动拼成 complex filtergraph，再叠 `-vf` 会报
/// "Simple and complex filtering cannot be used together"。
pub fn extract_image_thumbnail_ffmpeg(image_path: &Path, max_size: u32) -> Result<image::DynamicImage> {
    let ffmpeg_path = get_ffmpeg_path();

    let temp_output = std::env::temp_dir().join(format!("img_{}.jpg", uuid::Uuid::new_v4()));

    let scale_filter = if max_size > 0 {
        format!(
            "scale={}:{}:force_original_aspect_ratio=decrease",
            max_size, max_size
        )
    } else {
        String::new()
    };

    let mut args: Vec<&str> = vec!["-i", image_path.to_str().unwrap()];
    let filter_str; // 延长生命周期
    if !scale_filter.is_empty() {
        filter_str = scale_filter;
        args.extend_from_slice(&["-filter_complex", &filter_str]);
    }
    args.extend_from_slice(&[
        "-frames:v",
        "1",
        "-update",
        "1",
        "-q:v",
        "2",
        "-y",
        temp_output.to_str().unwrap(),
    ]);

    let output = Command::new(&ffmpeg_path)
        .args(&args)
        .output()
        .map_err(|e| {
            actix_web::error::ErrorInternalServerError(format!("FFmpeg 执行失败: {}", e))
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let _ = fs::remove_file(&temp_output);
        return Err(actix_web::error::ErrorInternalServerError(
            format!("FFmpeg 图片转换失败: {}", stderr)
        ));
    }

    let img = image::open(&temp_output)
        .map_err(|e| {
            let _ = fs::remove_file(&temp_output);
            actix_web::error::ErrorInternalServerError(format!("无法读取转换后的图片: {}", e))
        })?;

    let _ = fs::remove_file(&temp_output);
    Ok(img)
}

/// 从 CLIP (Clip Studio Paint) 文件的内嵌 SQLite 数据库中提取缩略图
///
/// .clip 文件结构：文件头部分 + 嵌入的 SQLite 数据库
/// SQLite 数据库中 CanvasPreview 表存储了 PNG 格式的缩略图
pub fn extract_clip_thumbnail(clip_path: &Path) -> Result<image::DynamicImage> {
    // 读取整个文件
    let data = fs::read(clip_path)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法读取 CLIP 文件: {}", e)))?;

    // 搜索 SQLite 魔数 "SQLite format 3\000"
    let sqlite_magic = b"SQLite format 3\x00";
    let offset = data.windows(sqlite_magic.len())
        .position(|window| window == sqlite_magic)
        .ok_or_else(|| actix_web::error::ErrorBadRequest("CLIP 文件中未找到 SQLite 数据库"))?;

    // 将 SQLite 部分写入临时文件（rusqlite 需要文件路径）
    let temp_db = std::env::temp_dir().join(format!("clip_{}.db", uuid::Uuid::new_v4()));
    fs::write(&temp_db, &data[offset..])
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法写入临时数据库: {}", e)))?;

    // 打开 SQLite 数据库并查询缩略图
    let conn = rusqlite::Connection::open(&temp_db)
        .map_err(|e| {
            let _ = fs::remove_file(&temp_db);
            actix_web::error::ErrorInternalServerError(format!("无法打开 CLIP 数据库: {}", e))
        })?;

    let image_data: Vec<u8> = conn.query_row(
        "SELECT ImageData FROM CanvasPreview LIMIT 1",
        [],
        |row| row.get(0),
    ).map_err(|e| {
        let _ = fs::remove_file(&temp_db);
        actix_web::error::ErrorInternalServerError(format!("无法从 CLIP 提取预览图: {}", e))
    })?;

    let _ = fs::remove_file(&temp_db);

    // 解码 PNG 数据为 DynamicImage
    let img = image::load_from_memory_with_format(&image_data, image::ImageFormat::Png)
        .or_else(|_| image::load_from_memory(&image_data))
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法解码 CLIP 预览图: {}", e)))?;

    Ok(img)
}

/// 使用 MuPDF 渲染 PDF 第一页为缩略图
pub fn extract_pdf_thumbnail(pdf_path: &Path) -> Result<image::DynamicImage> {
    let path_str = pdf_path.to_str()
        .ok_or_else(|| actix_web::error::ErrorBadRequest("无效的文件路径"))?;

    let doc = mupdf::Document::open(path_str)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法打开 PDF: {}", e)))?;

    let page = doc.load_page(0)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法加载 PDF 页面: {}", e)))?;

    let bounds = page.bounds()
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法获取页面尺寸: {}", e)))?;

    // 缩放到约 600px 宽
    let scale = if bounds.x1 - bounds.x0 > 0.0 {
        600.0 / (bounds.x1 - bounds.x0)
    } else {
        2.0
    };
    let matrix = mupdf::Matrix::new_scale(scale, scale);

    let pixmap = page.to_pixmap(&matrix, &mupdf::Colorspace::device_rgb(), false, true)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法渲染 PDF 页面: {}", e)))?;

    let width = pixmap.width() as u32;
    let height = pixmap.height() as u32;
    let samples = pixmap.samples();

    // MuPDF 输出 RGB 数据，转为 image::DynamicImage
    let img = image::RgbImage::from_raw(width, height, samples.to_vec())
        .ok_or_else(|| actix_web::error::ErrorInternalServerError("无法从像素数据创建图片"))?;

    Ok(image::DynamicImage::ImageRgb8(img))
}

// ============================================================================
// EXIF / HEIF Orientation → 像素转正（不改原文件）
// ============================================================================

/// 读取图片方向标记（1–8）。无标记或失败时返回 1（正向）。
/// 优先 exiftool（HEIC/JPEG 通用）；JPEG 再回退内置 APP1 解析。
pub fn probe_image_orientation(path: &Path) -> u8 {
    if let Some(v) = orientation_via_exiftool(path) {
        return v;
    }
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();
    if matches!(ext.as_str(), "jpg" | "jpeg") {
        if let Ok(bytes) = fs::read(path) {
            if let Some(v) = orientation_from_jpeg_exif(&bytes) {
                return v;
            }
        }
    }
    1
}

fn orientation_via_exiftool(path: &Path) -> Option<u8> {
    let exiftool = which_exiftool()?;
    let output = Command::new(exiftool)
        .args(["-n", "-s3", "-Orientation"])
        .arg(path)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let v: u8 = text.trim().parse().ok()?;
    if (1..=8).contains(&v) {
        Some(v)
    } else {
        None
    }
}

fn which_exiftool() -> Option<PathBuf> {
    for candidate in [
        "exiftool",
        "/opt/homebrew/bin/exiftool",
        "/usr/local/bin/exiftool",
        "/usr/bin/exiftool",
    ] {
        let p = PathBuf::from(candidate);
        if candidate == "exiftool" {
            if Command::new("exiftool").arg("-ver").output().ok()?.status.success() {
                return Some(p);
            }
        } else if p.exists() {
            return Some(p);
        }
    }
    None
}

/// 按 EXIF Orientation 把像素转成「正向显示」；orientation==1 时原样返回。
pub fn apply_exif_orientation(img: image::DynamicImage, orientation: u8) -> image::DynamicImage {
    match orientation {
        2 => img.fliph(),
        3 => img.rotate180(),
        4 => img.flipv(),
        5 => img.rotate90().fliph(),
        6 => img.rotate90(),
        7 => img.rotate270().fliph(),
        8 => img.rotate270(),
        _ => img,
    }
}

/// 探测方向并转正（缩略图生成入口）。
pub fn orient_image_for_display(path: &Path, img: image::DynamicImage) -> image::DynamicImage {
    let orientation = probe_image_orientation(path);
    if orientation <= 1 {
        return img;
    }
    apply_exif_orientation(img, orientation)
}

/// 从 JPEG APP1 Exif 读取 Orientation（tag 0x0112）。
fn orientation_from_jpeg_exif(data: &[u8]) -> Option<u8> {
    if data.len() < 4 || data[0] != 0xFF || data[1] != 0xD8 {
        return None;
    }
    let mut i = 2usize;
    while i + 4 <= data.len() {
        if data[i] != 0xFF {
            break;
        }
        let marker = data[i + 1];
        if marker == 0xD9 || marker == 0xDA {
            break;
        }
        if i + 4 > data.len() {
            break;
        }
        let len = u16::from_be_bytes([data[i + 2], data[i + 3]]) as usize;
        if len < 2 || i + 2 + len > data.len() {
            break;
        }
        let segment = &data[i + 4..i + 2 + len];
        i += 2 + len;
        // APP1 + "Exif\0\0"
        if marker == 0xE1 && segment.len() >= 14 && &segment[0..6] == b"Exif\0\0" {
            return orientation_from_tiff(&segment[6..]);
        }
    }
    None
}

fn orientation_from_tiff(tiff: &[u8]) -> Option<u8> {
    if tiff.len() < 8 {
        return None;
    }
    let le = match &tiff[0..2] {
        b"II" => true,
        b"MM" => false,
        _ => return None,
    };
    let read_u16 = |off: usize| -> Option<u16> {
        let b = tiff.get(off..off + 2)?;
        Some(if le {
            u16::from_le_bytes([b[0], b[1]])
        } else {
            u16::from_be_bytes([b[0], b[1]])
        })
    };
    let read_u32 = |off: usize| -> Option<u32> {
        let b = tiff.get(off..off + 4)?;
        Some(if le {
            u32::from_le_bytes([b[0], b[1], b[2], b[3]])
        } else {
            u32::from_be_bytes([b[0], b[1], b[2], b[3]])
        })
    };
    let ifd0 = read_u32(4)? as usize;
    let count = read_u16(ifd0)? as usize;
    for n in 0..count {
        let entry = ifd0 + 2 + n * 12;
        let tag = read_u16(entry)?;
        if tag != 0x0112 {
            continue;
        }
        let typ = read_u16(entry + 2)?;
        // SHORT (3) or LONG (4); value fits in the 4-byte value field
        let val = if typ == 3 {
            read_u16(entry + 8)? as u8
        } else {
            read_u32(entry + 8)? as u8
        };
        if (1..=8).contains(&val) {
            return Some(val);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn sample_probe_tiled() -> &'static str {
        r#"
[STREAM_GROUP]
index=0
id=0x3f1
nb_streams=4
type=Tile Grid
[COMPONENT]
nb_tiles=4
coded_width=2560
coded_height=1440
horizontal_offset=0
vertical_offset=0
width=2560
height=1440
[SUBCOMPONENT]
stream_index=0
tile_horizontal_offset=0
tile_vertical_offset=0
[/SUBCOMPONENT]
[SUBCOMPONENT]
stream_index=1
tile_horizontal_offset=1280
tile_vertical_offset=0
[/SUBCOMPONENT]
[SUBCOMPONENT]
stream_index=2
tile_horizontal_offset=0
tile_vertical_offset=720
[/SUBCOMPONENT]
[SUBCOMPONENT]
stream_index=3
tile_horizontal_offset=1280
tile_vertical_offset=720
[/SUBCOMPONENT]
[/COMPONENT]
DISPOSITION:default=1
TAG:title=Derived image
[/STREAM_GROUP]
[STREAM]
index=0
codec_name=hevc
width=1280
height=720
[/STREAM]
"#
    }

    #[test]
    fn parse_tile_grid_from_ffprobe() {
        let grid = parse_heif_tile_grid(sample_probe_tiled()).expect("tile grid");
        assert_eq!(grid.coded_width, 2560);
        assert_eq!(grid.coded_height, 1440);
        assert_eq!(grid.display_width, 2560);
        assert_eq!(grid.display_height, 1440);
        assert!(!grid.needs_display_crop());
        assert_eq!(grid.tiles.len(), 4);
        assert_eq!(
            grid.tiles[0],
            HeifTile {
                stream_index: 0,
                x: 0,
                y: 0
            }
        );
        assert_eq!(
            grid.tiles[3],
            HeifTile {
                stream_index: 3,
                x: 1280,
                y: 720
            }
        );
        assert_eq!(build_xstack_layout(&grid.tiles), "0_0|1280_0|0_720|1280_720");
    }

    fn sample_probe_tiled_padded() -> &'static str {
        // 真实 iPhone/sips HEIC：coded 按 tile 对齐 pad，ispe 为较小显示区
        r#"
[STREAM_GROUP]
index=0
id=0x7
nb_streams=6
type=Tile Grid
[COMPONENT]
nb_tiles=6
coded_width=1536
coded_height=1024
horizontal_offset=0
vertical_offset=0
width=1200
height=900
[SUBCOMPONENT]
stream_index=0
tile_horizontal_offset=0
tile_vertical_offset=0
[/SUBCOMPONENT]
[SUBCOMPONENT]
stream_index=1
tile_horizontal_offset=512
tile_vertical_offset=0
[/SUBCOMPONENT]
[SUBCOMPONENT]
stream_index=2
tile_horizontal_offset=1024
tile_vertical_offset=0
[/SUBCOMPONENT]
[SUBCOMPONENT]
stream_index=3
tile_horizontal_offset=0
tile_vertical_offset=512
[/SUBCOMPONENT]
[SUBCOMPONENT]
stream_index=4
tile_horizontal_offset=512
tile_vertical_offset=512
[/SUBCOMPONENT]
[SUBCOMPONENT]
stream_index=5
tile_horizontal_offset=1024
tile_vertical_offset=512
[/SUBCOMPONENT]
[/COMPONENT]
DISPOSITION:default=1
[/STREAM_GROUP]
"#
    }

    #[test]
    fn parse_padded_tile_grid_needs_display_crop() {
        let grid = parse_heif_tile_grid(sample_probe_tiled_padded()).expect("padded grid");
        assert_eq!(grid.coded_width, 1536);
        assert_eq!(grid.coded_height, 1024);
        assert_eq!(grid.display_width, 1200);
        assert_eq!(grid.display_height, 900);
        assert_eq!(grid.crop_x, 0);
        assert_eq!(grid.crop_y, 0);
        assert!(grid.needs_display_crop());
        assert_eq!(grid.tiles.len(), 6);
    }

    #[test]
    fn parse_ignores_stream_tile_dimensions_inside_group() {
        // -show_streams 会把单 tile 的 width/coded_width=512 打进同一段输出；
        // 不可覆盖 COMPONENT 的 ispe/coded 尺寸。
        let polluted = format!(
            "{}\n[STREAM]\nindex=0\ncoded_width=512\ncoded_height=512\nwidth=512\nheight=512\n[/STREAM]\n",
            sample_probe_tiled_padded()
        );
        let grid = parse_heif_tile_grid(&polluted).expect("padded grid");
        assert_eq!(grid.coded_width, 1536);
        assert_eq!(grid.display_width, 1200);
        assert!(grid.needs_display_crop());
    }

    #[test]
    fn parse_ignores_single_tile_or_missing_grid() {
        assert!(parse_heif_tile_grid("").is_none());
        assert!(parse_heif_tile_grid(
            r#"
[STREAM_GROUP]
type=Tile Grid
coded_width=100
coded_height=100
[SUBCOMPONENT]
stream_index=0
tile_horizontal_offset=0
tile_vertical_offset=0
[/SUBCOMPONENT]
[/STREAM_GROUP]
"#
        )
        .is_none());
    }

    fn fixture(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }

    fn install_test_tools(tools: &Path) {
        fs::create_dir_all(tools).unwrap();
        for name in ["ffmpeg", "ffprobe"] {
            let dest = tools.join(name);
            // Prefer pre-downloaded ReSourcer-bundled builds (HEIF tile aware).
            // Do NOT copy distro ffmpeg — Ubuntu 6.x / Homebrew 9.x behave differently
            // on tile grids than the binaries we ship under server/tools/.
            let alt = PathBuf::from("/tmp/heic-test").join(if name == "ffmpeg" {
                "ffmpeg-bundled"
            } else {
                "ffprobe-bundled"
            });
            let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("tools")
                .join(name);
            let src = if alt.exists() {
                alt
            } else if repo.exists() {
                repo
            } else {
                continue;
            };
            let _ = fs::copy(&src, &dest);
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let mut perms = fs::metadata(&dest).unwrap().permissions();
                perms.set_mode(0o755);
                fs::set_permissions(&dest, perms).unwrap();
            }
        }
    }

    #[test]
    fn tiled_heic_thumbnail_is_full_frame_not_single_tile() {
        let path = fixture("tiled_heic_c007.heic");
        if !path.exists() {
            eprintln!("skip: missing fixture {}", path.display());
            return;
        }
        let data = std::env::temp_dir().join(format!("rs-heif-test-{}", std::process::id()));
        let tools = data.join("tools");
        install_test_tools(&tools);
        // Missing binaries are downloaded by ensure_tool_binary (needs network).
        std::env::set_var("RESOURCER_DIR", &data);

        let img = extract_heif_thumbnail(&path, 300).expect("extract tiled heic");
        assert_eq!(img.width(), 300);
        assert_eq!(img.height(), 169);

        // Force stream 0 only: a single tile (often uniform wall / crop), not the
        // full derived image. Newer ffmpeg auto-assembles tile grids when no
        // -map is given, so compare against an explicit single-tile decode.
        let single = extract_single_tile_thumbnail_ffmpeg(&path, 300).expect("single tile");
        let rgb = img.to_rgb8();
        let single_rgb = single.to_rgb8();
        let mut diff: u64 = 0;
        let n = rgb.len().min(single_rgb.len()) as u64;
        for (a, b) in rgb.as_raw().iter().zip(single_rgb.as_raw().iter()) {
            diff += (*a as i16 - *b as i16).unsigned_abs() as u64;
        }
        let mad = diff as f64 / n as f64;
        assert!(
            mad > 5.0,
            "tiled extract should differ from single-tile decode (mad={})",
            mad
        );

        let _ = fs::remove_dir_all(&data);
    }

    /// Decode only HEIF stream 0 (one tile) scaled to `max_size`.
    fn extract_single_tile_thumbnail_ffmpeg(
        image_path: &Path,
        max_size: u32,
    ) -> Result<image::DynamicImage> {
        let ffmpeg_path = get_ffmpeg_path();
        let temp_output = std::env::temp_dir().join(format!("tile0_{}.jpg", uuid::Uuid::new_v4()));
        let scale = format!(
            "scale={}:{}:force_original_aspect_ratio=decrease",
            max_size, max_size
        );
        let output = Command::new(&ffmpeg_path)
            .args([
                "-i",
                image_path.to_str().unwrap(),
                "-map",
                "0:0",
                "-vf",
                &scale,
                "-frames:v",
                "1",
                "-update",
                "1",
                "-q:v",
                "2",
                "-y",
                temp_output.to_str().unwrap(),
            ])
            .output()
            .map_err(|e| {
                actix_web::error::ErrorInternalServerError(format!("FFmpeg 执行失败: {}", e))
            })?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let _ = fs::remove_file(&temp_output);
            return Err(actix_web::error::ErrorInternalServerError(format!(
                "FFmpeg 单 tile 转换失败: {}",
                stderr
            )));
        }
        let img = image::open(&temp_output).map_err(|e| {
            let _ = fs::remove_file(&temp_output);
            actix_web::error::ErrorInternalServerError(format!("无法读取单 tile 图片: {}", e))
        })?;
        let _ = fs::remove_file(&temp_output);
        Ok(img)
    }

    #[test]
    fn jpeg_orientation_6_probe_and_rotate_to_portrait() {
        let path = fixture("orient6_landscape_sensor.jpg");
        if !path.exists() {
            eprintln!("skip: missing fixture {}", path.display());
            return;
        }
        let orientation = probe_image_orientation(&path);
        assert_eq!(orientation, 6, "fixture must declare Orientation=6");

        let raw = image::open(&path).expect("open jpeg");
        assert_eq!((raw.width(), raw.height()), (120, 80));

        let oriented = orient_image_for_display(&path, raw);
        assert_eq!(
            (oriented.width(), oriented.height()),
            (80, 120),
            "Orientation=6 must become portrait pixels"
        );
        // Red bar was on the right of landscape sensor buffer; after Orientation=6
        // (rotate 90° CW) it becomes the bottom strip of the portrait image.
        let rgb = oriented.to_rgb8();
        let bottom = rgb.get_pixel(40, 115);
        let top = rgb.get_pixel(40, 5);
        assert!(
            bottom[0] > 180 && bottom[1] < 80,
            "bottom strip should be red after orient, got {:?}",
            bottom
        );
        assert!(
            top[2] > 150,
            "top strip should stay blue-ish, got {:?}",
            top
        );
    }

    #[test]
    fn apply_orientation_6_rotates_without_file() {
        let img = image::DynamicImage::ImageRgb8(image::RgbImage::from_pixel(
            10,
            4,
            image::Rgb([1, 2, 3]),
        ));
        let out = apply_exif_orientation(img, 6);
        assert_eq!((out.width(), out.height()), (4, 10));
    }
}
