---
id: RS-005
type: refactor
priority: 5
status: READY
attempt: 0
needs_human: false
created: 2026-10-04
---
# file_index 表改存相对路径

> 由 `docs/REFACTOR-RELATIVE-PATHS.md` 转来。那份文档写于更早期，正文声称
> 「数据模型（已改好）」，**但实际一行都没落地**（`models.rs` 仍是 `current_path`，
> `database.rs` 建表仍是 `current_path`/`folder_path`/`file_name`）。本卡已更正该描述。

## 背景

`file_index` 表存的是绝对路径（如 `/volume1/ReSourcer/sp/video.mp4`），带来三个问题：

1. NAS 上出现过 `/./volume1/...` 的路径污染，反复引发 source_url 丢失、重复记录
2. 换服务器或改挂载点要批量改库
3. API 响应把服务器文件系统路径泄露给前端

## 目标

路径字段改为相对于源文件夹，`@` 代表源文件夹根：`@/子目录/file.mp4`。

```sql
-- 现状
file_index (uuid, fingerprint, current_path, folder_path, file_name,
            file_type, extension, file_size, created_at, modified_at,
            indexed_at, source_url)

-- 目标
file_index (uuid, fingerprint,
            file_path     TEXT UNIQUE,   -- @/folder/file.mp4，NULL = pending/deleted
            source_folder TEXT NOT NULL, -- 所属源文件夹的绝对路径
            file_type, extension, file_size, created_at, modified_at,
            indexed_at, source_url)
```

- `current_path` → 并入 `file_path`
- `folder_path`、`file_name` → 从 `file_path` 动态算，不再入库
- 新增 `source_folder`，引用 `source_folders.folder_path`

## 范围

- `server/src/indexer/models.rs` —— `IndexedFile` 换字段，补 `file_name()` / `folder_path()` /
  `absolute_path()` / `to_relative()` 等派生方法
- `server/src/database.rs` —— 加列 + 数据迁移 + 索引
- `server/src/indexer/storage.rs` —— **改动量最大**，十余个查询要重写
  （`upsert_file`、`get_files_paginated`、`get_file_by_path`、`mark_missing_*`、`map_file_row` 等）
- `server/src/indexer/scanner.rs` —— 扫描时直接生成相对路径
- `server/src/indexer/handlers.rs` —— folder_path 参数与 breadcrumb 的路径转换
- `server/src/preview/{thumbnail,content}.rs` —— 由 UUID 查到相对路径再还原成绝对路径读文件
- `server/src/file/` —— rename 改 `file_path` 的文件名部分，move 改目录部分
- `server/src/transfer/{download,upload}/task_manager.rs` —— `complete_pending_file` 传相对路径
- `docs/API.md`、`docs/database.md` —— 必须同步
- **明确不做的**：`folder_index` 表这次不动（保持绝对路径），web / iOS 的适配拆到后续卡

## 实现方向

1. **服务端先改，API 保持兼容**：响应里继续给 `file_name` 这类计算字段，让前端暂时不用动
2. **启动时自动迁移**：`file_path = '@/' || replace(current_path, source_folder || '/', '')`，
   `source_folder` 通过 `folder_path` 前缀匹配 `source_folders` 表得到
3. SQLite 3.35 以下不支持 DROP COLUMN，旧列保留不再使用即可，不要为此重建表
4. 前端、iOS 的字段适配各自单独排卡

## Acceptance Criteria

- [ ] AC1: 新库启动后 `file_index` 有 `file_path`、`source_folder` 两列，扫描新文件写入的是 `@/...` 形式
- [ ] AC2: 拿一份含绝对路径的旧库启动 → 自动迁移，**迁移前后 file_index 行数一致**，
      随机抽 5 条比对 `source_folder || file_path去掉@` 与原 `current_path` 相等
- [ ] AC3: `GET /api/indexer/files` 响应仍含 `file_name`，前端不改也能正常列目录
- [ ] AC4: 缩略图与内容预览（`/api/preview/*`）对迁移后的文件仍能正确取到文件
- [ ] AC5: rename / move 之后 `file_path` 正确更新，且重启后仍指向同一文件
- [ ] AC6: `grep -rn current_path server/src` 只剩兼容用途，查询路径上不再使用
- [ ] AC7: `docs/API.md` 与 `docs/database.md` 已同步
- [ ] AC8: `./.ai/guard.sh` 通过
