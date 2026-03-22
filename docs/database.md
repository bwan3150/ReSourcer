# 数据库设计与索引机制

ReSourcer 使用 SQLite（WAL 模式）作为本地数据库，文件位于 `~/.config/re-sourcer/data.db`。

---

## 表结构总览

| 表名 | 用途 |
|------|------|
| `source_folders` | 用户添加的源文件夹配置 |
| `folder_index` | 文件夹扫描状态 |
| `file_index` | 文件索引（核心，每个文件一行） |
| `tags` | 标签定义（按源文件夹隔离） |
| `file_tags` | 文件↔标签多对多关联 |
| `download_history` | 下载任务历史 |
| `upload_history` | 上传任务历史 |

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
)
```

**关键设计**：`uuid` 和 `current_path` 都有 UNIQUE 约束，但意义不同：
- `uuid`：文件的永久身份，一经创建不再改变
- `current_path`：文件的当前位置，移动/重命名后会更新，文件消失后设为 NULL

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
)

-- 文件↔标签多对多关联，以 file_uuid 为外键
CREATE TABLE file_tags (
    file_uuid  TEXT NOT NULL,
    tag_id     INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY(file_uuid, tag_id)
)
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
