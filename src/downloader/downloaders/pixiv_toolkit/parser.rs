// Pixiv URL 解析器和 API 数据结构
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PixivIllustMeta {
    pub id: String,
    pub title: String,
    pub illust_type: u8, // 0: illust, 1: manga, 2: ugoira
    pub user_id: String,
    pub user_name: String,
    pub pages: Vec<PixivPage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PixivPage {
    pub urls: PixivUrls,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PixivUrls {
    pub original: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UgoiraMeta {
    pub src: String,
    #[serde(rename = "originalSrc")]
    pub original_src: String,
    pub mime_type: String,
    pub frames: Vec<UgoiraFrame>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UgoiraFrame {
    pub file: String,
    pub delay: u32, // 延迟时间（毫秒）
}

#[derive(Debug, Clone)]
pub struct PixivParser {
    pub illust_id: String,
}

impl PixivParser {
    /// 从 URL 中解析出作品 ID
    pub fn parse_url(url: &str) -> Result<Self, String> {
        // 支持的 URL 格式:
        // https://www.pixiv.net/artworks/123456
        // https://www.pixiv.net/member_illust.php?illust_id=123456

        let id = if let Some(captures) = regex::Regex::new(r"artworks/(\d+)")
            .unwrap()
            .captures(url)
        {
            captures.get(1).unwrap().as_str().to_string()
        } else if let Some(captures) = regex::Regex::new(r"illust_id=(\d+)")
            .unwrap()
            .captures(url)
        {
            captures.get(1).unwrap().as_str().to_string()
        } else {
            return Err("无法从 URL 中解析出作品 ID".to_string());
        };

        Ok(PixivParser { illust_id: id })
    }

    /// 构建作品信息 API URL
    pub fn build_illust_info_url(&self) -> String {
        format!("https://www.pixiv.net/ajax/illust/{}", self.illust_id)
    }

    /// 构建作品页面信息 API URL
    pub fn build_illust_pages_url(&self) -> String {
        format!(
            "https://www.pixiv.net/ajax/illust/{}/pages",
            self.illust_id
        )
    }

    /// 构建动图元数据 API URL
    pub fn build_ugoira_meta_url(&self) -> String {
        format!(
            "https://www.pixiv.net/ajax/illust/{}/ugoira_meta",
            self.illust_id
        )
    }

    /// 获取作品信息
    pub async fn fetch_illust_info(&self, token: &str) -> Result<PixivIllustMeta, String> {
        let client = reqwest::Client::new();

        // 获取基本信息
        let info_url = self.build_illust_info_url();
        let response = client
            .get(&info_url)
            .header("Cookie", format!("PHPSESSID={}", token))
            .header("Referer", "https://www.pixiv.net/")
            .send()
            .await
            .map_err(|e| format!("请求作品信息失败: {}", e))?;

        let json: serde_json::Value = response
            .json()
            .await
            .map_err(|e| format!("解析作品信息失败: {}", e))?;

        if json["error"].as_bool().unwrap_or(true) {
            return Err(format!(
                "获取作品信息失败: {}",
                json["message"].as_str().unwrap_or("Unknown error")
            ));
        }

        let body = &json["body"];
        let illust_type = body["illustType"].as_u64().unwrap_or(0) as u8;
        let title = body["title"].as_str().unwrap_or("untitled").to_string();
        let user_id = body["userId"].as_str().unwrap_or("").to_string();
        let user_name = body["userName"].as_str().unwrap_or("").to_string();

        // 如果是动图，直接返回（不需要获取页面信息）
        if illust_type == 2 {
            return Ok(PixivIllustMeta {
                id: self.illust_id.clone(),
                title,
                illust_type,
                user_id,
                user_name,
                pages: vec![],
            });
        }

        // 获取页面信息
        let pages_url = self.build_illust_pages_url();
        let pages_response = client
            .get(&pages_url)
            .header("Cookie", format!("PHPSESSID={}", token))
            .header("Referer", "https://www.pixiv.net/")
            .send()
            .await
            .map_err(|e| format!("请求页面信息失败: {}", e))?;

        let pages_json: serde_json::Value = pages_response
            .json()
            .await
            .map_err(|e| format!("解析页面信息失败: {}", e))?;

        if pages_json["error"].as_bool().unwrap_or(true) {
            return Err("获取页面信息失败".to_string());
        }

        let pages: Vec<PixivPage> = serde_json::from_value(pages_json["body"].clone())
            .map_err(|e| format!("解析页面数据失败: {}", e))?;

        Ok(PixivIllustMeta {
            id: self.illust_id.clone(),
            title,
            illust_type,
            user_id,
            user_name,
            pages,
        })
    }

    /// 获取动图元数据
    pub async fn fetch_ugoira_meta(&self, token: &str) -> Result<UgoiraMeta, String> {
        let client = reqwest::Client::new();
        let url = self.build_ugoira_meta_url();

        eprintln!("[Pixiv] 请求动图元数据: {}", url);

        let response = client
            .get(&url)
            .header("Cookie", format!("PHPSESSID={}", token))
            .header("Referer", "https://www.pixiv.net/")
            .send()
            .await
            .map_err(|e| format!("请求动图元数据失败: {}", e))?;

        let status = response.status();
        eprintln!("[Pixiv] 动图元数据响应状态: {}", status);

        let json: serde_json::Value = response
            .json()
            .await
            .map_err(|e| format!("解析动图元数据失败: {}", e))?;

        eprintln!("[Pixiv] 动图元数据响应: {}", serde_json::to_string_pretty(&json).unwrap_or_else(|_| "无法格式化".to_string()));

        if json["error"].as_bool().unwrap_or(true) {
            let error_msg = json["message"].as_str().unwrap_or("Unknown error");
            eprintln!("[Pixiv] API 返回错误: {}", error_msg);
            return Err(format!("获取动图元数据失败: {}", error_msg));
        }

        let meta: UgoiraMeta = serde_json::from_value(json["body"].clone())
            .map_err(|e| format!("解析动图元数据失败: {}", e))?;

        Ok(meta)
    }
}
