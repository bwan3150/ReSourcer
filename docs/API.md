# ReSourcer API Documentation

Base URL: `http://localhost:1234`

## Classifier API

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
    "hidden": false
  }
]
```

### POST `/api/classifier/settings/save`
保存设置

**Request Body:**
```json
{
  "source_folder": "/path/to/folder",
  "hidden_folders": ["folder1", "folder2"]
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
  "status": "success",
  "folder_name": "new_folder"
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
  "new_name": "new_name" // optional
}
```

**Response:**
```json
{
  "status": "success",
  "new_path": "/path/to/category/file.jpg",
  "old_path": "/path/to/file.jpg"
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

**Response:** 文件二进制内容，带对应的 Content-Type

---

## Downloader API

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
  }
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

### POST `/api/downloader/task`
创建下载任务

**Request Body:**
```json
{
  "url": "https://example.com/video",
  "save_folder": "folder_name",
  "downloader": "YtDlp", // optional
  "format": "best" // optional
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
取消任务

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

---

## Uploader API

### POST `/api/uploader/upload`
上传文件

**Request:** Multipart form data

**Response:**
```json
{
  "status": "success",
  "message": "File uploaded"
}
```

### GET `/api/uploader/devices`
获取可用设备列表

**Response:**
```json
{
  "devices": []
}
```

### POST `/api/uploader/connect`
连接设备

**Request Body:**
```json
{
  "device_id": "device_uuid"
}
```

**Response:**
```json
{
  "status": "success"
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
- `GalleryDl`

### TaskStatus (Enum)
- `pending`
- `downloading`
- `completed`
- `failed`
- `cancelled`

### FileType
- `image`: jpg, jpeg, png, gif, webp, bmp
- `video`: mp4, mov, avi, mkv, webm, m4v
