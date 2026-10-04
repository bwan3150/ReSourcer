// 网页端静态文件托管
//
// 以前网页端是独立的 nginx 容器，再把 /api/ 反代回宿主机的 1234 端口，
// 那条反代在 Linux Docker 上（没有 host.docker.internal）很容易配错。
// 由服务端自己托管之后前后端同源，少一个容器也少一类部署问题。
use actix_web::{
    http::header::{self, HeaderValue},
    middleware::DefaultHeaders,
    web, HttpRequest, HttpResponse,
};
use std::path::{Path, PathBuf};

/// index.html 必须禁缓存：它引用的 assets 文件名带 hash，
/// 自更新替换目录后旧 assets 会被删掉，浏览器若拿着缓存的旧 index.html
/// 就会去请求已经不存在的文件，表现为整页白屏。
const INDEX_CACHE: &str = "no-cache, must-revalidate";
/// Vite 产物文件名带内容 hash，可以长期缓存
const ASSET_CACHE: &str = "public, max-age=31536000, immutable";

/// 返回 index.html，并带上禁缓存头
async fn serve_index(req: HttpRequest, root: web::Data<PathBuf>) -> HttpResponse {
    // default_service 也会接住没匹配上的 /api 路径。那些该是 404，
    // 回 index.html 会让前端把一页 HTML 当成 JSON 解析，错得莫名其妙。
    if req.path().starts_with("/api") {
        return HttpResponse::NotFound().json(serde_json::json!({ "error": "Not Found" }));
    }
    match actix_files::NamedFile::open_async(root.join("index.html")).await {
        Ok(file) => {
            let mut resp = file.into_response(&req);
            resp.headers_mut()
                .insert(header::CACHE_CONTROL, HeaderValue::from_static(INDEX_CACHE));
            resp
        }
        Err(_) => HttpResponse::NotFound().body("web assets not installed"),
    }
}

pub fn configure(cfg: &mut web::ServiceConfig, web_root: &Path) {
    let root = web_root.to_path_buf();

    cfg.app_data(web::Data::new(root.clone()))
        // 带内容 hash 的构建产物，长缓存
        .service(
            web::scope("/assets")
                .wrap(DefaultHeaders::new().add((header::CACHE_CONTROL, ASSET_CACHE)))
                .service(actix_files::Files::new("", root.join("assets"))),
        )
        // 根路径
        .route("/", web::get().to(serve_index))
        // 其余根目录下的静态文件（favicon、manifest 之类）
        .service(actix_files::Files::new("/", root.clone()).prefer_utf8(true))
        // SPA 回退：前端路由（/gallery、/settings…）在磁盘上没有对应文件
        .default_service(web::get().to(serve_index));
}

/// 读取网页端版本号：web_dir()/version.json 里的 version 字段
/// 构建产物里没有这个文件时返回 None（本地手动构建的 dist 就是这种情况）
pub fn installed_version(web_root: &Path) -> Option<String> {
    let data = std::fs::read(web_root.join("version.json")).ok()?;
    let v: serde_json::Value = serde_json::from_slice(&data).ok()?;
    v["version"].as_str().map(|s| s.to_string())
}
