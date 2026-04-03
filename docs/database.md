# 数据库设计与索引机制

ReSourcer 使用 SQLite（WAL 模式）作为本地数据库，文件位于 `<app_dir>/sqlite/data.db`。

`app_dir` 按优先级确定：
1. 环境变量 `RESOURCER_DIR`（开发环境）
2. 可执行文件目录（如果含 `config/` 子目录，部署环境）
3. 当前工作目录（兜底）

---

## 表结构总览

| 表名 | 用途 |
|------|------|
| `config` | 全局应用配置（单行） |
| `source_folders` | 用户添加的源文件夹配置 |
| `subfolder_order` | 文件夹自定义排序 |
| `folder_index` | 文件夹扫描状态 |
| `file_index` | 文件索引（核心，每个文件一行） |
| `tags` | 标签定义（按源文件夹隔离） |
| `file_tags` | 文件↔标签多对多关联 |
| `download_history` | 下载任务历史 |
| `upload_history` | 上传任务历史 |

---

## config（全局配置）

```sql
CREATE TABLE config (
    id              INTEGER PRIMARY KEY CHECK (id = 1),  -- 单行约束
    hidden_folders  TEXT NOT NULL DEFAULT '[]',           -- JSON 数组
    use_cookies     INTEGER NOT NULL DEFAULT 1,           -- 布尔值 0/1
    ignored_folders TEXT NOT NULL DEFAULT '["@eaDir","#recycle","$RECYCLE.BIN"]',  -- JSON 数组
    ignored_files   TEXT NOT NULL DEFAULT '[".DS_Store"]'  -- JSON 数组
);
```

单行表，`CHECK (id = 1)` 确保只有一行。`ignored_folders` 和 `ignored_files` 用于过滤 NAS 系统文件夹和特殊文件。

---

## source_folders（源文件夹管理）

```sql
CREATE TABLE source_folders (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    folder_path TEXT NOT NULL UNIQUE,     -- 文件夹路径
    is_selected INTEGER NOT NULL DEFAULT 0,  -- 是否为当前选中的源
    created_at  TEXT NOT NULL             -- RFC3339 时间戳
);
```

管理用户添加的所有源文件夹，`is_selected` 标记当前激活的源。

---

## subfolder_order（文件夹排序）

```sql
CREATE TABLE subfolder_order (
    folder_path TEXT PRIMARY KEY,         -- 文件夹路径
    order_list  TEXT NOT NULL DEFAULT '[]'  -- JSON 数组，存储子文件夹名的排列顺序
);
```

存储任意层级文件夹的自定义排序。替代了旧版 `category_order` 表（初始化时自动删除旧表）。

---

## file_index（核心表）

```sql
CREATE TABLE file_index (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid         TEXT UNIQUE NOT NULL,   -- 文件身份证，全局唯一，不随重索引改变
    fingerprint  TEXT NOT NULL,          -- 预留字段（暂未使用）
    current_path TEXT UNIQUE,            -- 当前磁盘路径，NULL 表示文件已不存在
    folder_path  TEXT NOT NULL,          -- 所在文件夹路径
    file_name    TEXT NOT NULL,
    file_type    TEXT NOT NULL,          -- image / video / gif / audio / pdf / other
    extension    TEXT NOT NULL,
    file_size    INTEGER NOT NULL,
    created_at   TEXT NOT NULL,
    modified_at  TEXT NOT NULL,
    indexed_at   TEXT NOT NULL,
    source_url   TEXT                    -- 下载来源 URL（手动复制的文件为 NULL）
);
```

**关键设计**：`uuid` 和 `current_path` 都有 UNIQUE 约束，但意义不同：
- `uuid`：文件的永久身份，一经创建不再改变
- `current_path`：文件的当前位置，移动/重命名后会更新，文件消失后设为 NULL

**索引：**
```sql
CREATE INDEX idx_file_folder ON file_index(folder_path);
CREATE INDEX idx_file_modified ON file_index(modified_at);
```

---

## folder_index（文件夹索引）

```sql
CREATE TABLE folder_index (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    path          TEXT UNIQUE NOT NULL,    -- 文件夹路径
    parent_path   TEXT,                    -- 父文件夹路径（根源文件夹为 NULL）
    source_folder TEXT NOT NULL,           -- 所属源文件夹
    name          TEXT NOT NULL,           -- 文件夹名称
    depth         INTEGER NOT NULL DEFAULT 0,  -- 在层级中的深度
    file_count    INTEGER DEFAULT 0,       -- 文件夹内文件数
    indexed_at    TEXT NOT NULL,           -- RFC3339 时间戳
    files_scanned INTEGER NOT NULL DEFAULT 1   -- 0=仅扫描了子文件夹, 1=已扫描文件
);
```

**索引：**
```sql
CREATE INDEX idx_folder_parent ON folder_index(parent_path);
CREATE INDEX idx_folder_source ON folder_index(source_folder);
```

---

## download_history（下载历史）

```sql
CREATE TABLE download_history (
    id         TEXT PRIMARY KEY,          -- 任务 ID
    url        TEXT NOT NULL,             -- 下载 URL
    platform   TEXT NOT NULL,             -- 平台标识（pixiv, youtube, x 等）
    status     TEXT NOT NULL,             -- completed / failed / cancelled
    file_name  TEXT,                      -- 下载后的文件名
    file_path  TEXT,                      -- 下载后的文件路径
    error      TEXT,                      -- 失败时的错误信息
    created_at TEXT NOT NULL,             -- RFC3339 时间戳
    file_uuid  TEXT                       -- 索引后的文件 UUID
);
```

自动维护上限 **5000 条**记录，超出后删除最旧的记录。

---

## upload_history（上传历史）

```sql
CREATE TABLE upload_history (
    id            TEXT PRIMARY KEY,       -- 任务 ID
    file_name     TEXT NOT NULL,          -- 上传的文件名
    target_folder TEXT NOT NULL,          -- 目标文件夹
    status        TEXT NOT NULL,          -- completed / failed
    file_size     INTEGER NOT NULL,       -- 文件大小（字节）
    error         TEXT,                   -- 失败时的错误信息
    created_at    TEXT NOT NULL,          -- RFC3339 时间戳
    file_uuid     TEXT                    -- 索引后的文件 UUID
);
```

自动维护上限 **5000 条**记录。

---

## Tag 系统

### 表结构

```sql
-- 标签定义，按源文件夹隔离（不同源文件夹的同名标签互不干扰）
CREATE TABLE tags (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    source_folder TEXT NOT NULL,
    name          TEXT NOT NULL,
    color         TEXT NOT NULL DEFAULT '#007AFF',
    created_at    TEXT NOT NULL,
    UNIQUE(source_folder, name)
);

-- 文件↔标签多对多关联，以 file_uuid 为外键
CREATE TABLE file_tags (
    file_uuid  TEXT NOT NULL,
    tag_id     INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY(file_uuid, tag_id)
);
```

**索引：**
```sql
CREATE INDEX idx_tags_source ON tags(source_folder);
CREATE INDEX idx_file_tags_file ON file_tags(file_uuid);
CREATE INDEX idx_file_tags_tag ON file_tags(tag_id);
```

### 打 Tag 流程（全量替换）

```sql
-- 先清除该文件原有的所有标签
DELETE FROM file_tags WHERE file_uuid = 'abc-123'

-- 再插入新的关联
INSERT INTO file_tags (file_uuid, tag_id, created_at)
VALUES ('abc-123', 1, '2026-01-01T00:00:00Z'),
       ('abc-123', 2, '2026-01-01T00:00:00Z')
```

### 查询文件的 Tag

```sql
SELECT t.*
FROM tags t
INNER JOIN file_tags ft ON t.id = ft.tag_id
WHERE ft.file_uuid = 'abc-123'
ORDER BY t.name ASC
```

---

## 索引机制

### 惰性索引（首次打开文件夹）

文件索引**不在添加源文件夹时建立**，而是用户第一次打开某个文件夹时触发：

```
用户打开 /data/art/pixiv
  → GET /api/indexer/files?folder_path=/data/art/pixiv
  → is_folder_indexed() 返回 false
  → 同步扫描该文件夹 scan_folder()
  → 写入 file_index，返回文件列表
```

好处：只索引用户实际访问过的文件夹，不会在启动时阻塞。

### 增量更新（再次打开）

```
is_folder_indexed() → true（已扫描过）
needs_rescan() 比较文件夹 mtime 和 indexed_at
  → 文件夹有变化：后台启动 scan_folder，立即返回旧数据
  → 无变化：直接返回缓存数据
```

scan_folder 内部还有一层优化：对比每个文件的 `mtime`，未变化的文件直接跳过，不写数据库。

### 全量重建（force 模式）

用户手动点击"重新索引"时触发，`POST /api/indexer/scan { force: true }`：

```
scan_source_folder()        → 递归遍历整个源文件夹，upsert 所有文件
mark_missing_for_source()   → 检查 file_index 中有路径的记录，磁盘不存在的设 current_path = NULL
```

**重点**：不使用 DELETE，而是 upsert + 标记缺失。这样 UUID 始终保留，tag 等绑定数据不会丢失。

---

## UUID 的生命周期

UUID 在文件**首次被索引**时生成，之后通过以下机制保持稳定：

```sql
-- fast_upsert：ON CONFLICT(current_path) 保留已有 uuid
INSERT INTO file_index (uuid, current_path, ...)
VALUES (新生成的UUID, '/data/art/img.jpg', ...)
ON CONFLICT(current_path) DO UPDATE SET
    file_name   = excluded.file_name,
    file_size   = excluded.file_size,
    modified_at = excluded.modified_at
    -- uuid 不在更新列表里，始终保留原值
```

| 操作 | UUID 变化 |
|------|-----------|
| 重新索引（文件路径不变） | 不变 |
| 文件移动/重命名 | 不变（`update_file_path` 只更新 `current_path`） |
| 文件被删除后重新放入 | **新 UUID**（路径第一次出现，当作新文件） |
| 文件内容修改（mtime 变化） | 不变 |

---

## 下载文件的 source_url

下载任务完成后立即调用 `index_single_file`，传入来源 URL：

```rust
index_single_file("/data/art/img.jpg", "/data/art", Some("https://pixiv.net/artworks/12345"))
```

写入时用 `COALESCE` 保护已有 URL 不被覆盖：

```sql
ON CONFLICT(uuid) DO UPDATE SET
    source_url = COALESCE(excluded.source_url, file_index.source_url)
    -- 新值为 NULL 时保留旧值
```

---

## 整体数据流

```
文件系统                       数据库
─────────                     ──────────────────────────────────────
/data/art/
  pixiv/
    img.jpg  ──首次打开──→    file_index
                               ├─ uuid: abc-123
                               ├─ current_path: /data/art/pixiv/img.jpg
                               └─ source_url: https://pixiv.net/...
                                       │
                               file_tags (abc-123 → tag 1, 2)
                                       │
                               tags (1: pixiv, 2: figure)

    img.jpg 被删除  ──────→    current_path = NULL（uuid 保留，tag 保留）
    img_new.jpg 新增 ─────→    新 uuid，新的 file_index 行
    img.jpg 移动到子目录 ──→    update_file_path() 只更新 current_path，uuid 不变
```

---

## 数据库配置

```sql
PRAGMA journal_mode = WAL;      -- 允许读写并发
PRAGMA busy_timeout = 5000;     -- 写冲突时等待 5 秒
PRAGMA synchronous = NORMAL;    -- WAL 模式下推荐设置
```

批量写入时使用事务分批提交（每 500 条一个事务），平衡写入性能和写锁占用时间。

---

## 迁移机制

### ALTER TABLE 迁移

在 `init_db()` 中执行，使用 `ALTER TABLE ... ADD COLUMN` 配合 `.ok()` 忽略已存在的列：

| 表 | 新增列 | 默认值 |
|------|--------|--------|
| `file_index` | `source_url TEXT` | NULL |
| `folder_index` | `files_scanned INTEGER NOT NULL` | 1 |
| `config` | `ignored_folders TEXT` | `'["@eaDir","#recycle","$RECYCLE.BIN"]'` |
| `config` | `ignored_files TEXT` | `'[".DS_Store"]'` |
| `download_history` | `file_uuid TEXT` | NULL |
| `upload_history` | `file_uuid TEXT` | NULL |

### JSON → SQLite 迁移

首次运行时自动迁移旧版 JSON 配置文件：

- `config.json` → `config` 表 + `source_folders` 表
- `download_history.json` → `download_history` 表
- `upload_history.json` → `upload_history` 表
- `category_order.json` → `subfolder_order` 表

迁移成功后删除旧 JSON 文件，使用 `INSERT OR IGNORE` 防止重复。

### 数据类型迁移

- `.clip` 文件的 `file_type` 从 `'other'` 迁移为 `'image'`

---

## 完整索引一览

```sql
-- file_index 性能索引
CREATE INDEX idx_file_folder ON file_index(folder_path);
CREATE INDEX idx_file_modified ON file_index(modified_at);

-- folder_index 层级导航
CREATE INDEX idx_folder_parent ON folder_index(parent_path);
CREATE INDEX idx_folder_source ON folder_index(source_folder);

-- Tag 查询
CREATE INDEX idx_tags_source ON tags(source_folder);
CREATE INDEX idx_file_tags_file ON file_tags(file_uuid);
CREATE INDEX idx_file_tags_tag ON file_tags(tag_id);
```
