// Pixiv 动图 (Ugoira) 下载和转换
use super::parser::{PixivParser, UgoiraMeta};
use std::path::PathBuf;
use tokio::fs;
use tokio::io::AsyncWriteExt;

/// 下载动图 ZIP 文件
///
/// # 参数
/// - url: Pixiv 动图 URL
/// - token: PHPSESSID token
/// - output_dir: 输出目录
///
/// # 返回
/// - Ok((zip_path, meta)): ZIP 文件路径和元数据
/// - Err(错误信息): 下载失败
pub async fn download_ugoira_zip(
    url: String,
    token: String,
    output_dir: String,
) -> Result<(String, UgoiraMeta), String> {
    eprintln!("[Pixiv Ugoira] 开始下载动图 ZIP: {}", url);

    // 1. 解析 URL
    let parser = PixivParser::parse_url(&url)?;

    // 2. 获取动图元数据
    let meta = parser.fetch_ugoira_meta(&token).await?;

    eprintln!("[Pixiv Ugoira] 动图帧数: {}", meta.frames.len());
    eprintln!("[Pixiv Ugoira] ZIP URL: {}", meta.original_src);

    // 3. 下载 ZIP 文件
    let client = reqwest::Client::new();
    let response = client
        .get(&meta.original_src)
        .header("Referer", "https://www.pixiv.net/")
        .header("Cookie", format!("PHPSESSID={}", token))
        .send()
        .await
        .map_err(|e| format!("下载 ZIP 失败: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("下载 ZIP 失败，状态码: {}", response.status()));
    }

    let bytes = response
        .bytes()
        .await
        .map_err(|e| format!("读取 ZIP 数据失败: {}", e))?;

    // 4. 保存 ZIP 文件
    fs::create_dir_all(&output_dir)
        .await
        .map_err(|e| format!("创建输出目录失败: {}", e))?;

    let zip_filename = format!("{}_ugoira.zip", parser.illust_id);
    let zip_path = PathBuf::from(&output_dir).join(&zip_filename);

    let mut file = fs::File::create(&zip_path)
        .await
        .map_err(|e| format!("创建 ZIP 文件失败: {}", e))?;

    file.write_all(&bytes)
        .await
        .map_err(|e| format!("写入 ZIP 文件失败: {}", e))?;

    eprintln!("[Pixiv Ugoira] ZIP 已保存: {}", zip_path.display());

    Ok((zip_path.to_string_lossy().to_string(), meta))
}

/// 将动图 ZIP 转换为 GIF
///
/// # 参数
/// - zip_path: ZIP 文件路径
/// - meta: 动图元数据
/// - output_dir: 输出目录
/// - illust_id: 作品 ID
/// - progress_callback: 进度回调 (0.0 - 1.0)
///
/// # 返回
/// - Ok(gif_path): GIF 文件路径
/// - Err(错误信息): 转换失败
pub async fn convert_ugoira_to_gif<F>(
    zip_path: String,
    meta: UgoiraMeta,
    output_dir: String,
    illust_id: String,
    mut progress_callback: F,
) -> Result<String, String>
where
    F: FnMut(f32) + Send + 'static,
{
    eprintln!("[Pixiv Ugoira] 开始转换为 GIF: {}", zip_path);

    // 1. 创建临时目录用于解压帧
    let temp_dir = PathBuf::from(&output_dir).join(format!("{}_frames", illust_id));
    fs::create_dir_all(&temp_dir)
        .await
        .map_err(|e| format!("创建临时目录失败: {}", e))?;

    // 2. 解压 ZIP 文件
    let zip_file = std::fs::File::open(&zip_path)
        .map_err(|e| format!("打开 ZIP 文件失败: {}", e))?;

    let mut archive = zip::ZipArchive::new(zip_file)
        .map_err(|e| format!("读取 ZIP 文件失败: {}", e))?;

    let archive_len = archive.len();
    eprintln!("[Pixiv Ugoira] 解压 {} 个帧...", archive_len);

    for i in 0..archive_len {
        let mut file = archive
            .by_index(i)
            .map_err(|e| format!("读取 ZIP 文件条目失败: {}", e))?;

        let outpath = temp_dir.join(file.name());

        if file.is_dir() {
            std::fs::create_dir_all(&outpath)
                .map_err(|e| format!("创建目录失败: {}", e))?;
        } else {
            if let Some(p) = outpath.parent() {
                if !p.exists() {
                    std::fs::create_dir_all(&p)
                        .map_err(|e| format!("创建父目录失败: {}", e))?;
                }
            }
            let mut outfile = std::fs::File::create(&outpath)
                .map_err(|e| format!("创建文件失败: {}", e))?;
            std::io::copy(&mut file, &mut outfile)
                .map_err(|e| format!("写入文件失败: {}", e))?;
        }

        progress_callback(0.3 * (i as f32 / archive_len as f32));
    }

    // 3. 使用 image 和 gif crate 生成 GIF
    use image::{io::Reader as ImageReader, RgbaImage};
    use gif::{Encoder, Frame, Repeat};

    eprintln!("[Pixiv Ugoira] 开始生成 GIF...");

    // 读取第一帧以获取尺寸
    let first_frame_path = temp_dir.join(&meta.frames[0].file);
    let first_img = ImageReader::open(&first_frame_path)
        .map_err(|e| format!("打开第一帧失败: {}", e))?
        .decode()
        .map_err(|e| format!("解码第一帧失败: {}", e))?;

    let (width, height) = (first_img.width() as u16, first_img.height() as u16);

    eprintln!("[Pixiv Ugoira] GIF 尺寸: {}x{}", width, height);

    // 创建 GIF 编码器
    let gif_filename = format!("{}_ugoira.gif", illust_id);
    let gif_path = PathBuf::from(&output_dir).join(&gif_filename);

    let gif_file = std::fs::File::create(&gif_path)
        .map_err(|e| format!("创建 GIF 文件失败: {}", e))?;

    let mut encoder = Encoder::new(gif_file, width, height, &[])
        .map_err(|e| format!("创建 GIF 编码器失败: {}", e))?;

    encoder
        .set_repeat(Repeat::Infinite)
        .map_err(|e| format!("设置 GIF 循环失败: {}", e))?;

    // 逐帧添加到 GIF
    for (i, frame_info) in meta.frames.iter().enumerate() {
        let frame_path = temp_dir.join(&frame_info.file);

        let img = ImageReader::open(&frame_path)
            .map_err(|e| format!("打开帧 {} 失败: {}", frame_info.file, e))?
            .decode()
            .map_err(|e| format!("解码帧 {} 失败: {}", frame_info.file, e))?;

        // 转换为 RGBA
        let rgba_img: RgbaImage = img.to_rgba8();

        // 创建 GIF 帧
        let mut rgba_raw = rgba_img.into_raw();
        let mut frame = Frame::from_rgba_speed(width, height, &mut rgba_raw, 10);

        // 设置延迟时间（GIF 使用 1/100 秒为单位）
        frame.delay = (frame_info.delay / 10) as u16;

        encoder
            .write_frame(&frame)
            .map_err(|e| format!("写入 GIF 帧失败: {}", e))?;

        progress_callback(0.3 + 0.7 * ((i + 1) as f32 / meta.frames.len() as f32));
    }

    drop(encoder);

    eprintln!("[Pixiv Ugoira] GIF 已生成: {}", gif_path.display());

    // 4. 清理临时目录
    fs::remove_dir_all(&temp_dir)
        .await
        .map_err(|e| format!("清理临时目录失败: {}", e))?;

    progress_callback(1.0);

    Ok(gif_path.to_string_lossy().to_string())
}
