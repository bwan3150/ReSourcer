---
id: RS-002
type: feature
priority: 2
status: READY
attempt: 0
needs_human: false
created: 2026-09-11
---

# server 端支持「收藏 / 精选」标记

## 背景

现在只能靠 tag 给文件分类，没有一个轻量的「收藏」动作。
需要两个级别：**收藏**（个人标记）和**精选**（更高一档，用于挑出代表作）。

本卡只做 **server 端**：存储 + 接口 + 文档。web / iOS 的界面是后续独立任务。

## 范围

- 新模块 `server/src/favorite/`，**严格照 `server/src/playlist/` 的四件套**：
  `mod.rs`（只登记 routes）/ `models.rs` / `storage.rs`（SQL）/ `handlers.rs`（HTTP）
- `server/src/database.rs` —— 加表
- `server/src/main.rs` —— 挂载路由
- `docs/API.md` + `docs/database.md` —— **必须同步，guard 会检查**
- **明确不做的**：不碰 web / iOS；不改动 `tags` / `file_tags` 现有逻辑

## 实现方向

- 表 `favorites(file_uuid TEXT PRIMARY KEY, level TEXT NOT NULL, created_at TEXT NOT NULL)`，
  `level` 取 `favorite` / `featured`。用 `CREATE TABLE IF NOT EXISTS`，跟现有风格一致。
- 文件被删除/移动时不要留下孤儿记录 —— 至少查询时要能容忍 `file_index` 里已不存在的 uuid。
- 接口（前缀 `/api/favorite`）：
  - `POST /toggle` —— body `{uuid, level}`，已存在同级则取消，返回当前状态
  - `GET /list` —— 支持 `level`、分页，返回完整文件信息（复用 `indexer` 的 `map_file_row`，别自己拼）
  - `GET /status?uuids=a,b,c` —— 批量查，给列表页用；**不要让前端 N 次单查**

## Acceptance Criteria

- [ ] AC1: `cargo check` 与 `cargo test` 通过；新模块是四件套结构，`handlers.rs` 里没有 SQL
- [ ] AC2: 起服务后 `POST /api/favorite/toggle` 两次同一 uuid → 第一次标记成功，第二次取消，返回体如实反映状态
- [ ] AC3: `GET /api/favorite/list?level=favorite` 返回刚标记的文件，含文件名等完整信息
- [ ] AC4: `GET /api/favorite/status?uuids=...` 一次返回多个 uuid 的状态
- [ ] AC5: **重启服务后收藏仍在**（这条必须真的重启进程验证，不能只看内存）
- [ ] AC6: `docs/API.md` 和 `docs/database.md` 已更新；`./.ai/guard.sh` 通过
