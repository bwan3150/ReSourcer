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
| GET | `/api/transfer/download/tasks` | 获取活跃下载任务列表 |
| GET | `/api/transfer/download/task/{id}` | 获取单个下载任务 |
| DELETE | `/api/transfer/download/task/{id}` | 取消/删除下载任务 |
| GET | `/api/transfer/download/history` | 获取下载历史（分页） |
| DELETE | `/api/transfer/download/history` | 清空下载历史 |
| GET | `/api/transfer/download/ytdlp/version` | 获取 yt-dlp 版本 |
| POST | `/api/transfer/download/ytdlp/update` | 更新 yt-dlp |

### 传输操作 API - 上传 (`/api/transfer/upload`)
| 方法 | 路径 | 描述 |
|------|------|------|
| POST | `/api/transfer/upload/task` | 上传文件 |
| GET | `/api/transfer/upload/tasks` | 获取活跃上传任务列表 |
| GET | `/api/transfer/upload/task/{id}` | 获取单个上传任务 |
| DELETE | `/api/transfer/upload/task/{id}` | 删除上传任务 |
| POST | `/api/transfer/upload/tasks/clear` | 清空已完成任务 |
| GET | `/api/transfer/upload/history` | 获取上传历史（分页） |

### 索引器 API (`/api/indexer`)
| 方法 | 路径 | 描述 |
|------|------|------|
| POST | `/api/indexer/scan` | 扫描源文件夹 |
| GET | `/api/indexer/status` | 获取扫描状态 |
| GET | `/api/indexer/files` | 获取文件列表（分页） |
| GET | `/api/indexer/file` | 根据 UUID 获取文件 |
| GET | `/api/indexer/folders` | 获取子文件夹列表 |
| GET | `/api/indexer/breadcrumb` | 获取面包屑路径 |

### 标签 API (`/api/tag`)
| 方法 | 路径 | 描述 |
|------|------|------|
| GET | `/api/tag/list` | 获取标签列表 |
| POST | `/api/tag/create` | 创建标签 |
| PUT | `/api/tag/update/{id}` | 更新标签 |
| DELETE | `/api/tag/delete/{id}` | 删除标签 |
| GET | `/api/tag/file` | 获取文件的标签 |
| POST | `/api/tag/file` | 设置文件标签 |
| POST | `/api/tag/files` | 批量获取文件标签 |

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
| GET | `/api/preview/files` | 获取文件夹内文件列表 |
| GET | `/api/preview/content/{path}` | 获取文件内容 |

### 文件系统浏览 API (`/api/browser`)
| 方法 | 路径 | 描述 |
|------|------|------|
| POST | `/api/browser/browse` | 浏览目录 |
| POST | `/api/browser/create` | 创建目录 |

---

## 认证机制

所有 API（除白名单外）需要 API Key 认证，支持三种方式：

1. **Header**: `X-API-Key: <key>`
2. **Cookie**: `api_key=<key>`
3. **URL 参数**: `?key=<key>`

**无需认证的端点**:
- `GET /api/health`
- `POST /api/auth/verify`
- `GET /api/app`

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
  "uuid": "file-uuid",
  "new_name": "new_name.jpg"
}
```

**Response:**
```json
{
  "status": "success",
  "uuid": "file-uuid",
  "new_path": "/path/to/new_name.jpg"
}
```

### POST `/api/file/move`
移动文件到其他文件夹

**Request Body:**
```json
{
  "uuid": "file-uuid",
  "target_folder": "/path/to/target",
  "new_name": "optional_new_name.jpg"
}
```

| 字段 | 必填 | 描述 |
|------|------|------|
| `uuid` | 是 | 文件 UUID |
| `target_folder` | 是 | 目标文件夹路径 |
| `new_name` | 否 | 可选的新文件名 |

**Response:**
```json
{
  "status": "success",
  "uuid": "file-uuid",
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
      "created": "2025-01-01 12:00:00",
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
打开文件所在文件夹（系统文件管理器）

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
检测 URL 对应的平台和下载器

**Request Body:**
```json
{
  "url": "https://example.com/video"
}
```

**Response:**
```json
{
  "platform": "youtube",
  "downloader": "ytdlp",
  "confidence": 1.0,
  "platform_name": "YouTube",
  "requires_auth": false
}
```

### POST `/api/transfer/download/task`
创建下载任务

**Request Body:**
```json
{
  "url": "https://example.com/video",
  "save_folder": "folder_name",
  "downloader": "ytdlp",
  "format": "best"
}
```

| 字段 | 必填 | 描述 |
|------|------|------|
| `url` | 是 | 下载链接 |
| `save_folder` | 是 | 保存文件夹名 |
| `downloader` | 否 | 下载器类型 (`ytdlp` / `pixiv_toolkit`) |
| `format` | 否 | 下载格式 |

**Response:**
```json
{
  "status": "success",
  "task_id": "uuid",
  "message": "下载任务已创建"
}
```

### GET `/api/transfer/download/tasks`
获取活跃下载任务列表

**Response:**
```json
{
  "status": "success",
  "tasks": [
    {
      "id": "uuid",
      "url": "https://example.com/video",
      "platform": "youtube",
      "downloader": "ytdlp",
      "status": "downloading",
      "progress": 45.5,
      "speed": "2.5MB/s",
      "eta": "00:30",
      "save_folder": "folder_name",
      "file_name": "video.mp4",
      "file_path": "/path/to/video.mp4",
      "file_uuid": "file-uuid",
      "error": null,
      "created_at": "2025-10-06T12:00:00Z"
    }
  ]
}
```

### GET `/api/transfer/download/task/{id}`
获取单个任务状态

**Path Parameter:**
- `id`: 任务 ID

**Response:**
```json
{
  "status": "success",
  "task": { "...DownloadTask" }
}
```

### DELETE `/api/transfer/download/task/{id}`
取消任务或删除记录

**Path Parameter:**
- `id`: 任务 ID

**Response:**
```json
{
  "status": "success",
  "message": "任务已取消"
}
```

### GET `/api/transfer/download/history`
获取下载历史（分页）

**Query Parameters:**
- `offset` (可选): 偏移量，默认 0
- `limit` (可选): 每页数量，默认 50，最大 200
- `status` (可选): 按状态筛选

**Response:**
```json
{
  "items": [ "...DownloadTask[]" ],
  "total": 100,
  "offset": 0,
  "limit": 50,
  "has_more": true
}
```

### DELETE `/api/transfer/download/history`
清空下载历史

**Response:**
```json
{
  "status": "success",
  "message": "历史记录已清空"
}
```

### GET `/api/transfer/download/ytdlp/version`
获取 yt-dlp 版本信息

**Response:**
```json
{
  "version": "2024.12.23",
  "installed": true
}
```

### POST `/api/transfer/download/ytdlp/update`
更新 yt-dlp 到最新版本

**Response (成功):**
```json
{
  "status": "success",
  "output": "Updated yt-dlp to version ..."
}
```

**Response (失败):**
```json
{
  "error": "Update failed: ..."
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
获取活跃上传任务列表

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
      "file_uuid": "file-uuid",
      "error": null,
      "created_at": "2025-01-01T12:00:00Z"
    }
  ]
}
```

### GET `/api/transfer/upload/task/{task_id}`
获取单个任务详情

**Path Parameter:**
- `task_id`: 任务 ID

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
  "file_uuid": "file-uuid",
  "error": null,
  "created_at": "2025-01-01T12:00:00Z"
}
```

### DELETE `/api/transfer/upload/task/{task_id}`
删除任务（活跃任务或历史记录）

**Path Parameter:**
- `task_id`: 任务 ID

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

### GET `/api/transfer/upload/history`
获取上传历史（分页）

**Query Parameters:**
- `offset` (可选): 偏移量，默认 0
- `limit` (可选): 每页数量，默认 50，最大 200
- `status` (可选): 按状态筛选

**Response:**
```json
{
  "items": [ "...UploadTask[]" ],
  "total": 100,
  "offset": 0,
  "limit": 50,
  "has_more": true
}
```

---

## 索引器 API

### POST `/api/indexer/scan`
扫描源文件夹，建立文件索引

**Request Body:**
```json
{
  "source_folder": "/path/to/folder",
  "force": false
}
```

| 字段 | 必填 | 描述 |
|------|------|------|
| `source_folder` | 是 | 源文件夹路径 |
| `force` | 否 | 是否强制重新扫描，默认 false |

**Response:**
```json
{
  "status": "started",
  "scanned_files": 0,
  "scanned_folders": 0
}
```

### GET `/api/indexer/status`
获取当前扫描状态

**Response:**
```json
{
  "is_scanning": false,
  "scanned_files": 1234,
  "scanned_folders": 56
}
```

### GET `/api/indexer/files`
获取文件列表（分页）

**Query Parameters:**
- `folder_path` (必填): 文件夹路径
- `offset` (可选): 偏移量，默认 0
- `limit` (可选): 每页数量，默认 50，最大 200
- `file_type` (可选): 按文件类型筛选
- `sort` (可选): 排序字段

**Response:**
```json
{
  "files": [
    {
      "uuid": "file-uuid",
      "fingerprint": "hash",
      "current_path": "/path/to/file.jpg",
      "folder_path": "/path/to/folder",
      "file_name": "file.jpg",
      "file_type": "image",
      "extension": ".jpg",
      "file_size": 102400,
      "created_at": "2025-01-01T12:00:00Z",
      "modified_at": "2025-01-01T12:00:00Z",
      "indexed_at": "2025-01-01T12:00:00Z",
      "source_url": null
    }
  ],
  "total": 100,
  "offset": 0,
  "limit": 50,
  "has_more": true
}
```

### GET `/api/indexer/file`
根据 UUID 获取单个文件信息

**Query Parameters:**
- `uuid` (必填): 文件 UUID

**Response:**
```json
{
  "uuid": "file-uuid",
  "fingerprint": "hash",
  "current_path": "/path/to/file.jpg",
  "folder_path": "/path/to/folder",
  "file_name": "file.jpg",
  "file_type": "image",
  "extension": ".jpg",
  "file_size": 102400,
  "created_at": "2025-01-01T12:00:00Z",
  "modified_at": "2025-01-01T12:00:00Z",
  "indexed_at": "2025-01-01T12:00:00Z",
  "source_url": null
}
```

**404 Response:** 文件未找到

### GET `/api/indexer/folders`
获取子文件夹列表

**Query Parameters:**
- `parent_path` 或 `source_folder` (至少提供一个)

**Response:**
```json
[
  {
    "path": "/path/to/folder",
    "parent_path": "/path/to/parent",
    "source_folder": "/path/to/source",
    "name": "folder_name",
    "depth": 1,
    "file_count": 42,
    "subfolder_count": 3,
    "indexed_at": "2025-01-01T12:00:00Z"
  }
]
```

### GET `/api/indexer/breadcrumb`
获取文件夹面包屑路径

**Query Parameters:**
- `folder_path` (必填): 文件夹路径

**Response:**
```json
[
  { "name": "Source", "path": "/path/to/source" },
  { "name": "Category", "path": "/path/to/source/category" },
  { "name": "Subfolder", "path": "/path/to/source/category/subfolder" }
]
```

---

## 标签 API

### GET `/api/tag/list?source_folder=<path>`
获取指定源文件夹的所有标签

**Query Parameters:**
- `source_folder` (必填): 源文件夹路径

**Response:**
```json
[
  {
    "id": 1,
    "source_folder": "/path/to/source",
    "name": "标签名",
    "color": "#ff0000",
    "created_at": "2025-01-01T12:00:00Z"
  }
]
```

### POST `/api/tag/create`
创建新标签

**Request Body:**
```json
{
  "source_folder": "/path/to/source",
  "name": "标签名",
  "color": "#ff0000"
}
```

| 字段 | 必填 | 描述 |
|------|------|------|
| `source_folder` | 是 | 源文件夹路径 |
| `name` | 是 | 标签名称 |
| `color` | 否 | 标签颜色（十六进制） |

**Response:**
```json
{
  "id": 1,
  "source_folder": "/path/to/source",
  "name": "标签名",
  "color": "#ff0000",
  "created_at": "2025-01-01T12:00:00Z"
}
```

### PUT `/api/tag/update/{id}`
更新标签

**Path Parameter:**
- `id`: 标签 ID

**Request Body:**
```json
{
  "name": "新标签名",
  "color": "#00ff00"
}
```

所有字段均为可选。

**Response:**
```json
{
  "success": true
}
```

### DELETE `/api/tag/delete/{id}`
删除标签

**Path Parameter:**
- `id`: 标签 ID

**Response:**
```json
{
  "success": true
}
```

### GET `/api/tag/file?file_uuid=<uuid>`
获取指定文件的标签列表

**Query Parameters:**
- `file_uuid` (必填): 文件 UUID

**Response:**
```json
{
  "file_uuid": "file-uuid",
  "tags": [
    {
      "id": 1,
      "source_folder": "/path/to/source",
      "name": "标签名",
      "color": "#ff0000",
      "created_at": "2025-01-01T12:00:00Z"
    }
  ]
}
```

### POST `/api/tag/file`
设置文件的标签（替换现有标签）

**Request Body:**
```json
{
  "file_uuid": "file-uuid",
  "tag_ids": [1, 2, 3]
}
```

**Response:**
```json
{
  "success": true
}
```

### POST `/api/tag/files`
批量获取多个文件的标签

**Request Body:**
```json
{
  "file_uuids": ["uuid1", "uuid2", "uuid3"]
}
```

**Response:**
```json
[
  {
    "file_uuid": "uuid1",
    "tags": [ "...Tag[]" ]
  },
  {
    "file_uuid": "uuid2",
    "tags": [ "...Tag[]" ]
  }
]
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
  "ignored_folders": ["node_modules"],
  "ignored_files": [".DS_Store"],
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
  "categories": ["cat1", "cat2"],
  "ignored_folders": ["node_modules"],
  "ignored_files": [".DS_Store"]
}
```

| 字段 | 必填 | 描述 |
|------|------|------|
| `source_folder` | 否 | 源文件夹路径 |
| `hidden_folders` | 否 | 隐藏文件夹列表 |
| `categories` | 否 | 分类列表 |
| `ignored_folders` | 否 | 忽略的文件夹名称 |
| `ignored_files` | 否 | 忽略的文件名称 |

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

### GET `/api/preview/thumbnail`
生成并返回图片/视频缩略图

**Query Parameters:**
- `path` 或 `uuid`: 文件路径或文件 UUID（二选一）
- `size` (可选): 缩略图尺寸，默认 300

**Response:** JPEG 图片二进制数据

### GET `/api/preview/files?folder=<path>`
获取文件夹内的文件列表

**Query Parameters:**
- `folder` (必填): 文件夹路径

**Response:**
```json
{
  "files": [
    {
      "name": "file.jpg",
      "path": "/path/to/file.jpg",
      "file_type": "image",
      "extension": ".jpg",
      "size": 102400,
      "created": "2025-01-01 12:00:00",
      "modified": "2025-01-01 12:00:00",
      "width": null,
      "height": null,
      "duration": null
    }
  ]
}
```

### GET `/api/preview/content/{path}`
获取文件内容（用于预览）

**Path Parameter:**
- `path`: URL 编码的文件路径

**Query Parameters:**
- `uuid` (可选): 使用 UUID 引用文件

**Response:** 文件二进制内容，带对应的 Content-Type

**特性:**
- 支持 Range 请求（206 Partial Content），用于视频流式播放
- 自动转码不支持的视频格式（WMV/FLV/AVI → MP4）
- 从 .clip 文件提取预览图
- HEVC hev1 → hvc1 转换（兼容 iOS AVPlayer）

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
- `youtube` / `YouTube`
- `bilibili` / `Bilibili`
- `x` / `X`
- `tiktok` / `TikTok`
- `pixiv` / `Pixiv`
- `xiaohongshu` / `Xiaohongshu`
- `unknown` / `Unknown`

### DownloaderType (Enum)
- `ytdlp` / `YtDlp`
- `pixiv_toolkit` / `PixivToolkit`

### TaskStatus (下载) (Enum)
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
- `audio`: mp3, wav, flac, aac, ogg, m4a
- `pdf`: pdf
- `other`: 其他格式
