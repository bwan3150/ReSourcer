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

### 画廊 API (`/api/gallery`)
| 方法 | 路径 | 描述 |
|------|------|------|
| GET | `/api/gallery/folders` | 获取文件夹列表 |
| GET | `/api/gallery/files` | 获取媒体文件列表 |
| GET | `/api/gallery/thumbnail` | 获取缩略图 |
| POST | `/api/gallery/rename` | 重命名文件 |
| POST | `/api/gallery/move` | 移动文件 |

### 分类器 API (`/api/classifier`)
| 方法 | 路径 | 描述 |
|------|------|------|
| GET | `/api/classifier/state` | 获取分类器状态 |
| GET | `/api/classifier/folders` | 获取文件夹列表 |
| GET | `/api/classifier/files` | 获取待分类文件 |
| GET | `/api/classifier/file/{path}` | 获取文件内容 |
| POST | `/api/classifier/settings/save` | 保存设置 |
| POST | `/api/classifier/folder/create` | 创建文件夹 |
| POST | `/api/classifier/move` | 移动文件 |
| POST | `/api/classifier/preset/load` | 加载预设 |
| POST | `/api/classifier/preset/save` | 保存预设（只读） |
| DELETE | `/api/classifier/preset/delete` | 删除预设（只读） |
| POST | `/api/classifier/sources/add` | 添加源文件夹 |
| POST | `/api/classifier/sources/remove` | 移除源文件夹 |
| POST | `/api/classifier/sources/switch` | 切换源文件夹 |
| POST | `/api/classifier/categories/reorder` | 分类排序 |

### 设置 API (`/api/settings`)
| 方法 | 路径 | 描述 |
|------|------|------|
| GET | `/api/settings/state` | 获取配置状态 |
| GET | `/api/settings/folders` | 获取子文件夹列表 |
| GET | `/api/settings/sources/list` | 列出所有源文件夹 |
| POST | `/api/settings/save` | 保存设置 |
| POST | `/api/settings/folder/create` | 创建文件夹 |
| POST | `/api/settings/sources/add` | 添加源文件夹 |
| POST | `/api/settings/sources/remove` | 移除源文件夹 |
| POST | `/api/settings/sources/switch` | 切换源文件夹 |

### 下载器 API (`/api/downloader`)
| 方法 | 路径 | 描述 |
|------|------|------|
| POST | `/api/downloader/detect` | 检测 URL 平台 |
| GET | `/api/downloader/config` | 获取配置和认证状态 |
| POST | `/api/downloader/config` | 保存配置 |
| GET | `/api/downloader/folders` | 获取文件夹列表 |
| GET | `/api/downloader/tasks` | 获取所有任务列表 |
| GET | `/api/downloader/task/{id}` | 获取单个任务状态 |
| GET | `/api/downloader/file/{path}` | 获取文件内容 |
| POST | `/api/downloader/task` | 创建下载任务 |
| POST | `/api/downloader/create-folder` | 创建文件夹 |
| POST | `/api/downloader/credentials/{platform}` | 上传认证信息 |
| POST | `/api/downloader/open-folder` | 打开文件所在目录 |
| DELETE | `/api/downloader/task/{id}` | 取消/删除任务 |
| DELETE | `/api/downloader/credentials/{platform}` | 删除认证信息 |
| DELETE | `/api/downloader/history` | 清空历史记录 |

### 上传器 API (`/api/uploader`)
| 方法 | 路径 | 描述 |
|------|------|------|
| GET | `/api/uploader/tasks` | 获取上传任务列表 |
| GET | `/api/uploader/task/{task_id}` | 获取单个任务详情 |
| POST | `/api/uploader/upload` | 上传文件（支持批量） |
| POST | `/api/uploader/tasks/clear` | 清空已完成任务 |
| DELETE | `/api/uploader/task/{task_id}` | 删除任务 |

### 文件系统 API (`/api/filesystem`)
| 方法 | 路径 | 描述 |
|------|------|------|
| POST | `/api/filesystem/browse` | 浏览目录 |
| POST | `/api/filesystem/create` | 创建目录 |

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

## 画廊 API

### GET `/api/gallery/folders`
获取所有文件夹列表（源文件夹 + 分类文件夹）

**Response:**
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

### GET `/api/gallery/files`
获取指定文件夹的所有媒体文件

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

### GET `/api/gallery/thumbnail`
生成并返回图片/视频缩略图

**Query Parameters:**
- `path`: 文件路径
- `size` (optional): 缩略图尺寸，默认 300

**Response:** JPEG 图片二进制数据

### POST `/api/gallery/rename`
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

### POST `/api/gallery/move`
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

---

## 分类器 API

### GET `/api/classifier/state`
获取分类器状态和配置

**Response:**
```json
{
  "source_folder": "/path/to/folder",
  "hidden_folders": ["folder1", "folder2"],
  "presets": [
    {
      "name": "preset_name",
      "categories": ["cat1", "cat2"]
    }
  ]
}
```

### GET `/api/classifier/folders`
获取文件夹列表

**Query Parameters:**
- `source_folder` (optional): 源文件夹路径

**Response:**
```json
[
  {
    "name": "folder_name",
    "hidden": false,
    "file_count": 10
  }
]
```

### POST `/api/classifier/settings/save`
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

### POST `/api/classifier/folder/create`
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
  "status": "success"
}
```

### GET `/api/classifier/files`
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

### POST `/api/classifier/move`
移动文件到分类文件夹

**Request Body:**
```json
{
  "file_path": "/path/to/file.jpg",
  "category": "category_name",
  "new_name": "new_name"
}
```

**Response:**
```json
{
  "status": "success",
  "moved_to": "/path/to/category/file.jpg",
  "final_name": "file.jpg"
}
```

### POST `/api/classifier/preset/load`
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

### POST `/api/classifier/preset/save`
保存预设（只读，不支持）

**Response:**
```json
{
  "error": "Presets are read-only and loaded from config/presets.json"
}
```

### DELETE `/api/classifier/preset/delete`
删除预设（只读，不支持）

**Response:**
```json
{
  "error": "Presets are read-only and loaded from config/presets.json"
}
```

### GET `/api/classifier/file/{path}`
获取文件内容（用于预览）

**Path Parameter:**
- `path`: URL编码的文件路径

**Response:** 文件二进制内容，带对应的 Content-Type，支持 Range 请求

### POST `/api/classifier/sources/add`
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

### POST `/api/classifier/sources/remove`
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

### POST `/api/classifier/sources/switch`
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

### POST `/api/classifier/categories/reorder`
保存分类顺序

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

---

## 设置 API

### GET `/api/settings/state`
获取配置状态

**Response:**
```json
{
  "source_folder": "/path/to/folder",
  "hidden_folders": ["folder1", "folder2"],
  "backup_source_folders": ["/path/to/backup1", "/path/to/backup2"]
}
```

### GET `/api/settings/folders`
获取指定源文件夹下的子文件夹列表

**Query Parameters:**
- `source_folder` (optional): 源文件夹路径

**Response:**
```json
[
  {
    "name": "folder_name",
    "hidden": false
  }
]
```

### POST `/api/settings/save`
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

### POST `/api/settings/folder/create`
创建文件夹

**Request Body:**
```json
{
  "folder_name": "new_folder"
}
```

**Response:**
```json
{
  "status": "success"
}
```

### GET `/api/settings/sources/list`
列出所有源文件夹（当前 + 备用）

**Response:**
```json
{
  "current": "/path/to/current",
  "backups": ["/path/to/backup1", "/path/to/backup2"]
}
```

### POST `/api/settings/sources/add`
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

### POST `/api/settings/sources/remove`
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

### POST `/api/settings/sources/switch`
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

---

## 下载器 API

### POST `/api/downloader/detect`
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

### GET `/api/downloader/config`
获取配置和认证状态

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

### POST `/api/downloader/config`
保存配置

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

### GET `/api/downloader/folders`
获取文件夹列表

**Query Parameters:**
- `source_folder` (optional): 源文件夹路径

**Response:**
```json
[
  {
    "name": "folder_name",
    "hidden": false
  }
]
```

### POST `/api/downloader/task`
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

### GET `/api/downloader/tasks`
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

### GET `/api/downloader/task/{id}`
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

### DELETE `/api/downloader/task/{id}`
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

### POST `/api/downloader/credentials/{platform}`
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

### DELETE `/api/downloader/credentials/{platform}`
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

### GET `/api/downloader/file/{path}`
获取文件内容（用于预览）

**Path Parameter:**
- `path`: URL编码的文件路径

**Response:** 文件二进制内容，带对应的 Content-Type

### POST `/api/downloader/open-folder`
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

### DELETE `/api/downloader/history`
清空历史记录

**Response:**
```json
{
  "status": "success",
  "message": "历史记录已清空"
}
```

### POST `/api/downloader/create-folder`
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

---

## 上传器 API

### POST `/api/uploader/upload`
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

### GET `/api/uploader/tasks`
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

### GET `/api/uploader/task/{task_id}`
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

### DELETE `/api/uploader/task/{task_id}`
删除任务（活跃任务或历史记录）

**Path Parameter:**
- `task_id`: 任务ID

**Response:**
```json
{
  "message": "任务已删除"
}
```

### POST `/api/uploader/tasks/clear`
清除所有已完成/失败的任务（历史记录）

**Response:**
```json
{
  "message": "已清除 5 个历史记录",
  "cleared_count": 5
}
```

---

## 文件系统 API

### POST `/api/filesystem/browse`
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

### POST `/api/filesystem/create`
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

