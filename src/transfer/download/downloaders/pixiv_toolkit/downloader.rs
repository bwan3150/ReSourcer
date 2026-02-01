// Pixiv 插画/漫画下载器
use super::parser::PixivParser;
use std::path::{Path, PathBuf};
use tokio::fs;
use tokio::io::AsyncWriteExt;

/// 下载单张图片
async fn download_image(
    url: &str,
    token: &str,
    output_path: &Path,
) -> Result<(), String> {
    eprintln!("[Pixiv] 下载图片: {}", url);

    let client = reqwest::Client::new();
    let response = client
        .get(url)
        .header("Referer", "https://www.pixiv.net/")
        .header("Cookie", format!("PHPSESSID={}", token))
        .send()
        .await
        .map_err(|e| format!("下载图片失败: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("下载失败，状态码: {}", response.status()));
    }

    let bytes = response
        .bytes()
        .await
        .map_err(|e| format!("读取图片数据失败: {}", e))?;

    let mut file = fs::File::create(output_path)
        .await
        .map_err(|e| format!("创建文件失败: {}", e))?;

    file.write_all(&bytes)
        .await
        .map_err(|e| format!("写入文件失败: {}", e))?;

    eprintln!("[Pixiv] 图片已保存: {}", output_path.display());

    Ok(())
}

/// 下载 Pixiv 插画/漫画的所有图片
///
/// # 参数
/// - url: Pixiv 作品 URL
/// - token: PHPSESSID token
/// - output_dir: 输出目录
/// - progress_callback: 进度回调 (当前进度, 总数)
///
/// # 返回
/// - Ok(文件路径列表): 下载成功
/// - Err(错误信息): 下载失败
pub async fn download_illust<F>(
    url: String,
    token: String,
    output_dir: String,
    mut progress_callback: F,
) -> Result<Vec<String>, String>
where
    F: FnMut(usize, usize) + Send + 'static,
{
    eprintln!("[Pixiv] 开始下载插画: {}", url);

    // 1. 解析 URL
    let parser = PixivParser::parse_url(&url)?;

    // 2. 获取作品信息
    let illust_meta = parser.fetch_illust_info(&token).await?;

    if illust_meta.illust_type == 2 {
        return Err("这是动图作品，请使用动图下载功能".to_string());
    }

    if illust_meta.pages.is_empty() {
        return Err("作品没有图片页面".to_string());
    }

    eprintln!(
        "[Pixiv] 作品信息: ID={}, 标题={}, 页数={}",
        illust_meta.id,
        illust_meta.title,
        illust_meta.pages.len()
    );

    // 3. 创建输出目录
    fs::create_dir_all(&output_dir)
        .await
        .map_err(|e| format!("创建输出目录失败: {}", e))?;

    // 4. 下载所有图片
    let total = illust_meta.pages.len();
    let mut downloaded_files = Vec::new();

    for (index, page) in illust_meta.pages.iter().enumerate() {
        let url = &page.urls.original;

        // 从 URL 提取文件扩展名
        let ext = url
            .split('.')
            .last()
            .unwrap_or("jpg");

        // 构建文件名
        let filename = if total == 1 {
            format!("{}_{}.{}", illust_meta.id, illust_meta.title, ext)
        } else {
            format!("{}_{}_{:03}.{}", illust_meta.id, illust_meta.title, index, ext)
        };

        let output_path = PathBuf::from(&output_dir).join(&filename);

        // 下载图片
        download_image(url, &token, &output_path).await?;

        downloaded_files.push(output_path.to_string_lossy().to_string());

        // 更新进度
        progress_callback(index + 1, total);
    }

    eprintln!("[Pixiv] 所有图片下载完成");

    Ok(downloaded_files)
}
