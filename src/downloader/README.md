# Downloader 模块

## 功能概述
下载器模块负责从各种网络平台下载视频、音频、图片等资源到本地指定文件夹。

## 文件结构

```
downloader/
├── README.md              # 本文件：模块说明文档
├── mod.rs                 # 模块入口，导出公共接口
├── models.rs              # 数据模型定义 < 150行
├── handlers.rs            # API 路由处理器 < 300行
├── config.rs              # 基础配置管理（主配置文件）< 150行
├── detector.rs            # URL 检测和下载器选择逻辑 < 150行
├── task_manager.rs        # 任务管理器 < 300行
├── auth/                  # 需要认证的平台管理模块（按网站分）
│   ├── mod.rs             # 认证模块入口
│   ├── x.rs               # X (Twitter) 认证管理 < 100行
│   └── pixiv.rs           # Pixiv 认证管理 < 100行
│   # (其他平台如 YouTube、Bilibili 暂不需要认证)
└── downloaders/           # 各类下载器实现（按下载工具分）
    ├── mod.rs             # 下载器模块入口
    ├── ytdlp.rs           # yt-dlp 下载器实现 < 250行
    └── (未来添加 gallery_dl.rs 用于 pixiv 等)
```

## 配置文件结构

配置文件存储在用户主目录下：`~/.config/re-sourcer/`

```
~/.config/re-sourcer/
├── config.json                    # 主配置文件
└── credentials/                   # 认证信息目录（仅需要认证的平台）
    ├── x/                         # X (Twitter) 认证
    │   └── cookies.txt            # X cookies
    └── pixiv/                     # Pixiv 认证
        ├── token.txt              # PHPSESSID token
        └── refresh_token.txt      # 刷新令牌（可选）
    # YouTube、Bilibili、TikTok 等暂不需要认证
```

## 模块职责

### config.rs (< 150行)
**只负责主配置文件管理**，不处理任何平台认证：
- `get_config_dir()`: 获取 `~/.config/re-sourcer/` 路径
- `get_credentials_dir()`: 获取 `credentials/` 路径
- `load_config()`: 加载 config.json
- `save_config()`: 保存 config.json
- `ConfigData`: 主配置结构（source_folder, hidden_folders, use_cookies）

### auth/mod.rs
认证模块总入口：
- 导出所有平台的认证模块
- `check_all_auth_status()`: 检查所有平台认证状态
- `AuthStatus`: 汇总的认证状态结构

### auth/x.rs (< 100行)
**专门处理 X (Twitter) 的认证**：
- `get_x_dir()`: 获取 `credentials/x/` 路径
- `get_cookies_path()`: 获取 cookies.txt 路径
- `has_cookies()`: 检查是否有 cookies
- `load_cookies()`: 读取 cookies 内容
- `save_cookies(content)`: 保存 cookies
- `delete_cookies()`: 删除 cookies

### auth/pixiv.rs (< 100行)
**专门处理 Pixiv 的认证**：
- `get_pixiv_dir()`: 获取 `credentials/pixiv/` 路径
- `get_token_path()`: 获取 token.txt 路径
- `get_refresh_token_path()`: 获取 refresh_token.txt 路径
- `has_token()`: 检查是否有 token
- `load_token()`: 读取 PHPSESSID
- `save_token(token)`: 保存 token
- `load_refresh_token()`: 读取刷新令牌
- `save_refresh_token(token)`: 保存刷新令牌
- `delete_all()`: 删除所有认证信息


### detector.rs (< 150行)
URL 检测逻辑：
- `detect(url)`: 返回 `DetectResponse`
- 平台匹配规则：
  - YouTube: `youtube.com`, `youtu.be` → YtDlp
  - Bilibili: `bilibili.com`, `b23.tv` → YtDlp
  - X: `x.com`, `twitter.com` → YtDlp
  - TikTok: `tiktok.com`, `douyin.com` → YtDlp
  - 小红书: `xiaohongshu.com` → YtDlp
  - Pixiv: `pixiv.net` → Pixiv

### task_manager.rs (< 300行)
任务队列管理：
- `TaskManager`: 使用 `Arc<Mutex<HashMap>>` 管理任务
- `create_task()`: 创建任务
- `get_task()`: 获取任务
- `update_progress()`: 更新进度
- `cancel_task()`: 取消任务
- 调用对应下载器执行下载

### downloaders/ytdlp.rs (< 250行)
yt-dlp 下载器：
- `download(task_id, url, platform, options)`: 执行下载
- `build_command()`: 构建命令，根据平台自动选择对应的 cookies
  - YouTube/Bilibili/TikTok URL → 无需认证，直接下载
  - X URL → 使用 `auth::x::get_cookies_path()` 如果存在
- `parse_progress()`: 解析进度输出
- `get_ytdlp_path()`: 获取可执行文件路径

### handlers.rs (< 300行)
API 实现：
- `POST /detect` - 调用 `detector::detect()`
- `POST /task` - 调用 `task_manager::create_task()`
- `GET /tasks` - 调用 `task_manager::get_all_tasks()`
- `GET /task/:id` - 调用 `task_manager::get_task()`
- `DELETE /task/:id` - 调用 `task_manager::cancel_task()`
- `GET /config` - 调用 `config::load_config()` + `auth::check_all_auth_status()`
- `POST /config` - 调用 `config::save_config()`
- `GET /folders` - 获取文件夹列表（类似 classifier）
- `POST /credentials/:platform` - 根据平台调用对应 auth 模块保存
- `DELETE /credentials/:platform` - 根据平台调用对应 auth 模块删除

## API 端点

### POST /api/downloader/detect
检测 URL 适用的下载器
```json
Request: { "url": "https://youtube.com/watch?v=xxx" }
Response: {
  "downloader": "ytdlp",
  "confidence": 1.0,
  "platform_name": "YouTube",
  "requires_auth": false
}
```

### POST /api/downloader/task
创建下载任务
```json
Request: {
  "url": "https://...",
  "downloader": "ytdlp",  // 可选
  "save_folder": "videos",  // 相对路径或空字符串
  "format": "best"  // 可选
}
Response: {
  "status": "success",
  "task_id": "uuid",
  "message": "任务已创建"
}
```

### GET /api/downloader/task/:id
获取任务状态（前端轮询）
```json
Response: {
  "status": "success",
  "task": {
    "id": "uuid",
    "url": "...",
    "downloader": "ytdlp",
    "status": "downloading",
    "progress": 45.5,
    "speed": "2.3MB/s",
    "eta": "00:05",
    "file_name": "video.mp4",
    "file_path": "/path/to/file"
  }
}
```

### POST /api/downloader/credentials/:platform
上传认证信息
```json
Request: {
  "content": "# Netscape HTTP Cookie File\n..."
}
Response: {
  "status": "success",
  "message": "认证信息已保存"
}
```

## 认证信息使用流程

1. **系统启动**: `auth::check_all_auth_status()` 检查 X 和 Pixiv 的认证状态
2. **创建任务**: 根据 URL 检测到**平台**（如 YouTube）和**下载器**（如 YtDlp）
3. **执行下载**:
   - YouTube/Bilibili/TikTok URL → `downloaders::ytdlp` → 无需认证直接下载
   - X URL → `downloaders::ytdlp` → 调用 `auth::x::get_cookies_path()`（如有）
   - Pixiv URL → `downloaders::gallery_dl`(未来) → 调用 `auth::pixiv::load_token()`
4. **认证缺失**: 如果需要认证的平台（X、Pixiv）没有认证信息，返回错误，前端提示上传

## 扩展新平台

添加新平台（如 Instagram）：
1. 创建 `auth/instagram.rs`
2. 创建 `downloaders/instagram.rs`（如果不用 yt-dlp）
3. 在 `detector.rs` 添加匹配规则
4. 在 `task_manager.rs` 添加调用逻辑
5. 在 `handlers.rs` 的 credentials 路由添加分支
