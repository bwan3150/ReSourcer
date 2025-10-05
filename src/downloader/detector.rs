// URL 检测器：根据 URL 判断平台和推荐的下载器
use super::models::{DetectResponse, DownloaderType, Platform};

// 检测 URL 的平台和下载器
pub fn detect(url: &str) -> DetectResponse {
    let url_lower = url.to_lowercase();

    // YouTube
    if url_lower.contains("youtube.com") || url_lower.contains("youtu.be") {
        return DetectResponse {
            platform: Platform::YouTube,
            downloader: DownloaderType::YtDlp,
            confidence: 1.0,
            platform_name: "YouTube".to_string(),
            requires_auth: false,
        };
    }

    // Bilibili
    if url_lower.contains("bilibili.com") || url_lower.contains("b23.tv") {
        return DetectResponse {
            platform: Platform::Bilibili,
            downloader: DownloaderType::YtDlp,
            confidence: 1.0,
            platform_name: "Bilibili".to_string(),
            requires_auth: false,
        };
    }

    // X (Twitter)
    if url_lower.contains("x.com") || url_lower.contains("twitter.com") {
        return DetectResponse {
            platform: Platform::X,
            downloader: DownloaderType::YtDlp,
            confidence: 1.0,
            platform_name: "X (Twitter)".to_string(),
            requires_auth: true, // X 需要认证
        };
    }

    // TikTok
    if url_lower.contains("tiktok.com") || url_lower.contains("douyin.com") {
        return DetectResponse {
            platform: Platform::TikTok,
            downloader: DownloaderType::YtDlp,
            confidence: 1.0,
            platform_name: "TikTok".to_string(),
            requires_auth: false,
        };
    }

    // 小红书
    if url_lower.contains("xiaohongshu.com") || url_lower.contains("xhslink.com") {
        return DetectResponse {
            platform: Platform::Xiaohongshu,
            downloader: DownloaderType::YtDlp,
            confidence: 0.9,
            platform_name: "小红书".to_string(),
            requires_auth: false,
        };
    }

    // Pixiv
    if url_lower.contains("pixiv.net") {
        return DetectResponse {
            platform: Platform::Pixiv,
            downloader: DownloaderType::PixivToolkit,
            confidence: 1.0,
            platform_name: "Pixiv".to_string(),
            requires_auth: true, // Pixiv 需要认证
        };
    }

    // 未知平台，尝试用 yt-dlp
    DetectResponse {
        platform: Platform::Unknown,
        downloader: DownloaderType::YtDlp,
        confidence: 0.3,
        platform_name: "Unknown".to_string(),
        requires_auth: false,
    }
}
