# 重构：file_index 表改为相对路径

## 背景

当前 `file_index` 表存储绝对路径（如 `/volume1/ReSourcer/sp/video.mp4`），导致：
1. NAS 上出现 `/./volume1/...` 路径污染，反复引发 source_url 丢失、重复记录等问题
2. 文件迁移（换服务器、改挂载点）需要批量更新数据库路径
3. API 响应泄露服务器文件系统路径（安全隐患）

## 目标

将 `file_index` 表的路径字段从绝对路径改为相对于源文件夹的路径。

## 新表结构

```sql
-- 旧结构
file_index (
    uuid, fingerprint, current_path, folder_path, file_name,
    file_type, extension, file_size, created_at, modified_at,
    indexed_at, source_url
)

-- 新结构
file_index (
    uuid TEXT UNIQUE NOT NULL,
    fingerprint TEXT NOT NULL,          -- 保留，未来查重用
    file_path TEXT UNIQUE,              -- 相对路径: @/folder/file.mp4 (NULL=pending/deleted)
    source_folder TEXT NOT NULL,        -- 对应的源文件夹绝对路径
    file_type TEXT NOT NULL,
    extension TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    modified_at TEXT NOT NULL,
    indexed_at TEXT NOT NULL,
    source_url TEXT
)
```

### 路径格式

- `@` = 源文件夹根目录
- `@/subfolder/file.mp4` = 源文件夹下的子目录文件
- `@/a/b/c/file.mp4` = 多层嵌套

### 删除的字段
- `current_path` → 合并为 `file_path`（相对路径）
- `folder_path` → 从 `file_path` 动态计算（`@/a/b/file.mp4` → `@/a/b`）
- `file_name` → 从 `file_path` 动态计算（`@/a/b/file.mp4` → `file.mp4`）

### 新增的字段
- `source_folder` — 文件所属的源文件夹（绝对路径，引用 `source_folders.folder_path`）

## 数据模型（已改好）

`server/src/indexer/models.rs` 中的 `IndexedFile` 已更新：

```rust
pub struct IndexedFile {
    pub uuid: String,
    pub fingerprint: String,
    pub file_path: Option<String>,      // @/folder/file.mp4
    pub source_folder: String,
    pub file_type: String,
    pub extension: String,
    pub file_size: i64,
    pub created_at: String,
    pub modified_at: String,
    pub indexed_at: String,
    pub source_url: Option<String>,
}

impl IndexedFile {
    fn file_name() -> String          // 从 file_path 提取
    fn folder_path() -> String        // 从 file_path 提取
    fn absolute_path() -> Option<String>  // source_folder + file_path
    fn to_relative(abs, source) -> String // 绝对 → @/ 相对
    fn relative_folder(abs, source) -> String
}
```

## 需要修改的文件清单

### 1. database.rs — 表结构 + 迁移
- ALTER TABLE 添加 `source_folder` 列
- 添加 `file_path` 列
- 迁移数据：`file_path = '@/' || replace(current_path, source_folder || '/', '')`
- 建新索引
- 可选：删除旧列（SQLite 不支持 DROP COLUMN，需要重建表或忽略）

### 2. indexer/storage.rs — 所有查询（最大改动量）
- `upsert_file` — 改用 file_path + source_folder
- `fast_upsert_file_with_conn` — 同上
- `create_pending_file` — 改参数
- `complete_pending_file` — 改参数，接收相对路径
- `get_files_paginated` — WHERE 条件改为 file_path LIKE '@/folder/%' 或新的 folder 匹配逻辑
- `get_file_by_uuid` — 改 SELECT 列
- `get_file_by_path` — 改为用相对路径查询
- `get_indexed_files_for_folder` — 改查询条件
- `update_file_path` — 改为更新 file_path
- `mark_missing_with_conn` — 改条件
- `mark_missing_for_source` — 改条件
- `map_file_row` — 改映射

### 3. indexer/scanner.rs — 扫描时生成相对路径
- `scan_folder` — 文件路径用 `IndexedFile::to_relative()`
- `scan_source_folder` — 同上
- `index_single_file` — 同上

### 4. indexer/handlers.rs — API handler
- `files` handler — folder_path 参数转为相对路径查询
- `file_by_uuid` — 返回时可能需要包含绝对路径供前端预览
- `folders` handler — folder_index 也需要改（或保持绝对路径）
- `breadcrumb` handler — 路径转换

### 5. preview/thumbnail.rs — 解析绝对路径读文件
- 通过 UUID 查到 file_path → absolute_path() → 读文件

### 6. preview/content.rs — 同上
- content handler 需要从相对路径解析出绝对路径

### 7. file/ (rename, move) — 文件操作
- rename: 更新 file_path 中的文件名部分
- move: 更新 file_path 的目录部分

### 8. transfer/download/task_manager.rs
- `complete_pending_file` 调用时传相对路径

### 9. transfer/upload/task_manager.rs
- 同上

### 10. config_api/migrate.rs — 路径迁移工具
- 迁移现在应该只需要改 source_folder 列

### 11. folder_index 表
- 考虑是否也改为相对路径，或保持绝对路径
- 如果改：path, parent_path 改为相对，source_folder 保留

## API 响应格式变化

前端（web + iOS）需要适配：

### /api/indexer/files 响应
```json
// 旧
{
  "uuid": "...",
  "current_path": "/volume1/ReSourcer/sp/file.mp4",
  "folder_path": "/volume1/ReSourcer/sp",
  "file_name": "file.mp4",
  ...
}

// 新
{
  "uuid": "...",
  "file_path": "@/file.mp4",
  "source_folder": "/volume1/ReSourcer/sp",
  "file_name": "file.mp4",  // 计算字段，方便前端
  ...
}
```

### 前端改动
- `api/preview.js` — thumbnailUrl/contentUrl 仍然用 UUID，不受影响
- 文件信息显示 — 适配新字段名
- 文件操作 — rename/move 仍用 UUID，不受影响

## 迁移策略

1. 服务端先改，保持 API 兼容（返回 file_name 计算字段）
2. 数据库启动时自动迁移旧数据
3. 前端适配新字段
4. iOS 适配新字段

## 注意事项

- SQLite 不支持 DROP COLUMN（3.35.0 以下），旧列保留但不再使用
- 迁移需要知道每个文件属于哪个 source_folder（通过 folder_path 前缀匹配 source_folders 表）
- `file_path` 的 UNIQUE 约束确保同一源文件夹下不会有重复
- `@` 前缀避免和实际文件名冲突
