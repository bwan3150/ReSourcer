# ReSourcer API Documentation

Base URL: `http://localhost:1234`

---

## API 目录 (Table of Contents)

### 全局 API
| 方法 | 路径 | 描述 |
|------|------|------|
| GET | `/api/health` | 健康检查（无需认证） |
| GET | `/api/config` | 获取全局配置 |
| GET | `/api/app` | 获取应用配置（版本、下载链接） |

### 认证 API (`/api/auth`)
| 方法 | 路径 | 描述 |
|------|------|------|
| POST | `/api/auth/verify` | 验证 API Key |
| GET | `/api/auth/check` | 检查当前 Key 有效性 |

### 文件操作 API (`/api/file`)
| 方法 | 路径 | 描述 |
|------|------|------|
| POST | `/api/file/rename` | 重命名文件 |
| POST | `/api/file/move` | 移动文件 |
| GET | `/api/file/info` | 获取文件信息 |

### 文件夹操作 API (`/api/folder`)
| 方法 | 路径 | 描述 |
|------|------|------|
| GET | `/api/folder/list` | 获取文件夹列表 |
| POST | `/api/folder/create` | 创建文件夹 |
| POST | `/api/folder/reorder` | 分类文件夹排序 |
| POST | `/api/folder/open` | 打开文件所在文件夹 |

### 传输操作 API - 下载 (`/api/transfer/download`)
| 方法 | 路径 | 描述 |
|------|------|------|
| POST | `/api/transfer/download/detect` | 检测 URL 平台 |
| POST | `/api/transfer/download/task` | 创建下载任务 |
| GET | `/api/transfer/download/tasks` | 获取下载任务列表 |
| GET | `/api/transfer/download/task/{id}` | 获取单个下载任务 |
| DELETE | `/api/transfer/download/task/{id}` | 取消/删除下载任务 |
| DELETE | `/api/transfer/download/history` | 清空下载历史 |

### 传输操作 API - 上传 (`/api/transfer/upload`)
| 方法 | 路径 | 描述 |
|------|------|------|
| POST | `/api/transfer/upload/task` | 上传文件 |
| GET | `/api/transfer/upload/tasks` | 获取上传任务列表 |
| GET | `/api/transfer/upload/task/{id}` | 获取单个上传任务 |
| DELETE | `/api/transfer/upload/task/{id}` | 删除上传任务 |
| POST | `/api/transfer/upload/tasks/clear` | 清空已完成任务 |

### 配置操作 API (`/api/config`)
| 方法 | 路径 | 描述 |
|------|------|------|
| GET | `/api/config` | 获取全局配置 |
| GET | `/api/config/state` | 获取配置状态 |
| POST | `/api/config/save` | 保存配置 |
| GET | `/api/config/download` | 获取下载器配置 |
| POST | `/api/config/download` | 保存下载器配置 |
| GET | `/api/config/sources` | 列出源文件夹 |
| POST | `/api/config/sources/add` | 添加源文件夹 |
| POST | `/api/config/sources/remove` | 移除源文件夹 |
| POST | `/api/config/sources/switch` | 切换源文件夹 |
| POST | `/api/config/credentials/{platform}` | 上传认证信息 |
| DELETE | `/api/config/credentials/{platform}` | 删除认证信息 |
| POST | `/api/config/preset/load` | 加载预设 |
| POST | `/api/config/preset/save` | 保存预设（只读） |
| DELETE | `/api/config/preset/delete` | 删除预设（只读） |

### 预览操作 API (`/api/preview`)
| 方法 | 路径 | 描述 |
|------|------|------|
| GET | `/api/preview/thumbnail` | 获取缩略图 |
| GET | `/api/preview/files` | 获取待分类文件列表 |
| GET | `/api/preview/content/{path}` | 获取文件内容 |

### 文件系统浏览 API (`/api/browser`)
| 方法 | 路径 | 描述 |
|------|------|------|
| POST | `/api/browser/browse` | 浏览目录 |
| POST | `/api/browser/create` | 创建目录 |

---

## 全局 API

### GET `/api/health`
健康检查（无需认证）

**Response:**
```json
{
  "status": "ok",
  "service": "ReSourcer"
}
```

### GET `/api/config`
获取全局配置

**Response:**
```json
{
  "source_folder": "/path/to/folder",
  "hidden_folders": ["folder1", "folder2"]
}
```

### GET `/api/app`
获取应用配置（版本、下载链接）

**Response:**
```json
{
  "version": "0.2.7-beta",
  "android_url": "https://...",
  "ios_url": "https://...",
  "github_url": "https://..."
}
```

---

## 认证 API

### POST `/api/auth/verify`
验证 API Key

**Request Body:**
```json
{
  "api_key": "your-api-key"
}
```

**Response:**
```json
{
  "valid": true
}
```

### GET `/api/auth/check`
检查当前请求的 API Key 是否有效（通过 Cookie）

**Response:**
```json
{
  "valid": true
}
```

---

## 文件操作 API

### POST `/api/file/rename`
重命名文件

**Request Body:**
```json
{
  "file_path": "/path/to/file.jpg",
  "new_name": "new_name.jpg"
}
```

**Response:**
```json
{
  "status": "success",
  "new_path": "/path/to/new_name.jpg"
}
```

### POST `/api/file/move`
移动文件到其他文件夹

**Request Body:**
```json
{
  "file_path": "/path/to/file.jpg",
  "target_folder": "/path/to/target"
}
```

**Response:**
```json
{
  "status": "success",
  "new_path": "/path/to/target/file.jpg"
}
```

### GET `/api/file/info?folder=<path>`
获取指定文件夹的所有媒体文件信息

**Query Parameters:**
- `folder`: 文件夹路径

**Response:**
```json
{
  "files": [
    {
      "name": "image.jpg",
      "path": "/path/to/image.jpg",
      "file_type": "image",
      "extension": ".jpg",
      "size": 102400,
      "modified": "2025-01-01 12:00:00",
      "width": null,
      "height": null,
      "duration": null
    }
  ]
}
```

---

## 文件夹操作 API

### GET `/api/folder/list`
获取文件夹列表

**Query Parameters (可选):**
- `source_folder`: 源文件夹路径（如果提供，返回该文件夹下的子文件夹；否则返回 gallery 样式的文件夹列表）

**Response (Gallery 模式 - 无参数):**
```json
{
  "folders": [
    {
      "name": "源文件夹",
      "path": "/path/to/folder",
      "is_source": true,
      "file_count": 10
    },
    {
      "name": "category1",
      "path": "/path/to/folder/category1",
      "is_source": false,
      "file_count": 5
    }
  ]
}
```

**Response (子文件夹模式 - 有 source_folder 参数):**
```json
[
  {
    "name": "folder_name",
    "hidden": false,
    "file_count": 10
  }
]
```

### POST `/api/folder/create`
创建新文件夹

**Request Body:**
```json
{
  "folder_name": "new_folder"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "文件夹创建成功",
  "folder_name": "new_folder"
}
```

### POST `/api/folder/reorder`
保存分类文件夹排序

**Request Body:**
```json
{
  "source_folder": "/path/to/folder",
  "category_order": ["cat1", "cat2", "cat3"]
}
```

**Response:**
```json
{
  "status": "success"
}
```

### POST `/api/folder/open`
打开文件所在文件夹

**Request Body:**
```json
{
  "path": "/path/to/file"
}
```

**Response:**
```json
{
  "status": "success"
}
```

---

## 传输操作 API - 下载

### POST `/api/transfer/download/detect`
检测URL对应的平台和下载器

**Request Body:**
```json
{
  "url": "https://example.com/video"
}
```

**Response:**
```json
{
  "platform": "YouTube",
  "downloader": "YtDlp",
  "supported": true
}
```

### POST `/api/transfer/download/task`
创建下载任务

**Request Body:**
```json
{
  "url": "https://example.com/video",
  "save_folder": "folder_name",
  "downloader": "YtDlp",
  "format": "best"
}
```

**Response:**
```json
{
  "status": "success",
  "task_id": "uuid",
  "message": "下载任务已创建"
}
```

### GET `/api/transfer/download/tasks`
获取所有任务列表（包含历史）

**Response:**
```json
{
  "status": "success",
  "tasks": [
    {
      "id": "uuid",
      "url": "https://example.com/video",
      "platform": "YouTube",
      "downloader": "YtDlp",
      "status": "downloading",
      "progress": 45.5,
      "speed": "2.5MB/s",
      "eta": "00:30",
      "save_folder": "folder_name",
      "file_name": "video.mp4",
      "file_path": "/path/to/video.mp4",
      "error": null,
      "created_at": "2025-10-06T12:00:00Z"
    }
  ]
}
```

### GET `/api/transfer/download/task/{id}`
获取单个任务状态

**Path Parameter:**
- `id`: 任务ID

**Response:**
```json
{
  "status": "success",
  "task": {
    "id": "uuid",
    "url": "https://example.com/video",
    "platform": "YouTube",
    "status": "downloading",
    "progress": 45.5
  }
}
```

### DELETE `/api/transfer/download/task/{id}`
取消任务或删除历史记录

**Path Parameter:**
- `id`: 任务ID

**Response:**
```json
{
  "status": "success",
  "message": "任务已取消"
}
```

### DELETE `/api/transfer/download/history`
清空历史记录

**Response:**
```json
{
  "status": "success",
  "message": "历史记录已清空"
}
```

---

## 传输操作 API - 上传

### POST `/api/transfer/upload/task`
上传文件（支持批量）

**Request:** Multipart form data
- `target_folder`: 目标文件夹路径
- `files`: 文件（可多个）

**Response:**
```json
{
  "task_ids": ["uuid1", "uuid2"],
  "message": "成功创建 2 个上传任务"
}
```

### GET `/api/transfer/upload/tasks`
获取所有上传任务（进行中 + 历史）

**Response:**
```json
{
  "tasks": [
    {
      "id": "uuid",
      "file_name": "file.jpg",
      "file_size": 102400,
      "target_folder": "/path/to/folder",
      "status": "uploading",
      "progress": 50.0,
      "uploaded_size": 51200,
      "error": null,
      "created_at": "2025-01-01T12:00:00Z"
    }
  ]
}
```

### GET `/api/transfer/upload/task/{task_id}`
获取单个任务详情

**Path Parameter:**
- `task_id`: 任务ID

**Response:**
```json
{
  "id": "uuid",
  "file_name": "file.jpg",
  "file_size": 102400,
  "target_folder": "/path/to/folder",
  "status": "completed",
  "progress": 100.0,
  "uploaded_size": 102400,
  "error": null,
  "created_at": "2025-01-01T12:00:00Z"
}
```

### DELETE `/api/transfer/upload/task/{task_id}`
删除任务（活跃任务或历史记录）

**Path Parameter:**
- `task_id`: 任务ID

**Response:**
```json
{
  "message": "任务已删除"
}
```

### POST `/api/transfer/upload/tasks/clear`
清除所有已完成/失败的任务（历史记录）

**Response:**
```json
{
  "message": "已清除 5 个历史记录",
  "cleared_count": 5
}
```

---

## 配置操作 API

### GET `/api/config/state`
获取配置状态

**Response:**
```json
{
  "source_folder": "/path/to/folder",
  "hidden_folders": ["folder1", "folder2"],
  "backup_source_folders": ["/path/to/backup1"],
  "presets": [
    {
      "name": "preset_name",
      "categories": ["cat1", "cat2"]
    }
  ]
}
```

### POST `/api/config/save`
保存设置

**Request Body:**
```json
{
  "source_folder": "/path/to/folder",
  "hidden_folders": ["folder1", "folder2"],
  "categories": ["cat1", "cat2"]
}
```

**Response:**
```json
{
  "status": "success"
}
```

### GET `/api/config/download`
获取下载器配置和认证状态

**Response:**
```json
{
  "source_folder": "/path/to/folder",
  "hidden_folders": ["folder1"],
  "use_cookies": false,
  "auth_status": {
    "x": true,
    "pixiv": false
  },
  "ytdlp_version": "2024.12.23"
}
```

### POST `/api/config/download`
保存下载器配置

**Request Body:**
```json
{
  "source_folder": "/path/to/folder",
  "hidden_folders": ["folder1"],
  "use_cookies": false
}
```

**Response:**
```json
{
  "status": "success"
}
```

### GET `/api/config/sources`
列出所有源文件夹（当前 + 备用）

**Response:**
```json
{
  "current": "/path/to/current",
  "backups": ["/path/to/backup1", "/path/to/backup2"]
}
```

### POST `/api/config/sources/add`
添加备用源文件夹

**Request Body:**
```json
{
  "folder_path": "/path/to/folder"
}
```

**Response:**
```json
{
  "status": "success"
}
```

### POST `/api/config/sources/remove`
移除备用源文件夹

**Request Body:**
```json
{
  "folder_path": "/path/to/folder"
}
```

**Response:**
```json
{
  "status": "success"
}
```

### POST `/api/config/sources/switch`
切换源文件夹

**Request Body:**
```json
{
  "folder_path": "/path/to/folder"
}
```

**Response:**
```json
{
  "status": "success"
}
```

### POST `/api/config/credentials/{platform}`
上传认证信息

**Path Parameter:**
- `platform`: 平台名称 (`x` 或 `pixiv`)

**Request Body:** 纯文本内容（cookies 或 token）

**Response:**
```json
{
  "status": "success",
  "message": "认证信息已保存"
}
```

### DELETE `/api/config/credentials/{platform}`
删除认证信息

**Path Parameter:**
- `platform`: 平台名称 (`x` 或 `pixiv`)

**Response:**
```json
{
  "status": "success",
  "message": "认证信息已删除"
}
```

### POST `/api/config/preset/load`
加载预设

**Request Body:**
```json
{
  "name": "preset_name"
}
```

**Response:**
```json
{
  "status": "success",
  "categories": ["cat1", "cat2"],
  "preset_name": "preset_name"
}
```

### POST `/api/config/preset/save`
保存预设（只读，不支持）

**Response:**
```json
{
  "error": "预设是只读的，从 config/presets.json 加载"
}
```

### DELETE `/api/config/preset/delete`
删除预设（只读，不支持）

**Response:**
```json
{
  "error": "预设是只读的，从 config/presets.json 加载"
}
```

---

## 预览操作 API

### GET `/api/preview/thumbnail?path=<file_path>&size=<size>`
生成并返回图片/视频缩略图

**Query Parameters:**
- `path`: 文件路径
- `size` (optional): 缩略图尺寸，默认 300

**Response:** JPEG 图片二进制数据

### GET `/api/preview/files`
获取待分类文件列表

**Response:**
```json
[
  {
    "name": "file.jpg",
    "path": "/path/to/file.jpg",
    "file_type": "image"
  }
]
```

### GET `/api/preview/content/{path}`
获取文件内容（用于预览）

**Path Parameter:**
- `path`: URL编码的文件路径

**Response:** 文件二进制内容，带对应的 Content-Type，支持 Range 请求

---

## 文件系统浏览 API

### POST `/api/browser/browse`
浏览目录

**Request Body:**
```json
{
  "path": "/path/to/directory"
}
```

若 `path` 为空，返回用户主目录。

**Response:**
```json
{
  "current_path": "/path/to/directory",
  "parent_path": "/path/to",
  "items": [
    {
      "name": "subfolder",
      "path": "/path/to/directory/subfolder",
      "is_directory": true
    },
    {
      "name": "file.txt",
      "path": "/path/to/directory/file.txt",
      "is_directory": false
    }
  ]
}
```

### POST `/api/browser/create`
创建新目录

**Request Body:**
```json
{
  "parent_path": "/path/to/parent",
  "directory_name": "new_folder"
}
```

**Response:**
```json
{
  "status": "success",
  "path": "/path/to/parent/new_folder"
}
```

---

## Data Models

### Platform (Enum)
- `YouTube`
- `Bilibili`
- `X`
- `TikTok`
- `Pixiv`
- `Xiaohongshu`
- `Unknown`

### DownloaderType (Enum)
- `YtDlp`
- `PixivToolkit`

### TaskStatus (Enum)
- `pending`
- `downloading`
- `completed`
- `failed`
- `cancelled`

### UploadStatus (Enum)
- `pending`
- `uploading`
- `completed`
- `failed`

### FileType (Enum)
- `image`: jpg, jpeg, png, webp, bmp, tiff, svg
- `video`: mp4, mov, avi, mkv, flv, wmv, m4v, webm
- `gif`: gif
- `other`: 其他格式
