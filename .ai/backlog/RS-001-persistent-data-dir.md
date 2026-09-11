---
id: RS-001
type: bug
priority: 1
status: READY
attempt: 0
needs_human: false
created: 2026-09-11
---
# server 数据目录可持久化，不再随 NAS 更新被清空

> 优先级排在收藏功能前面：这条是**正在丢数据**，其它是缺功能。

## 背景

`ops/setup.sh` 把程序装在 `/opt/re-sourcer/`，`sqlite/data.db`、`config/secret.json`、
`tools/` 都在这个目录下。**NAS 系统更新会清空 `/opt`**，于是数据库、密钥、配置全丢。

根因在 `server/src/static_files.rs::app_dir()`：它把「程序所在目录」直接当成「数据目录」——
这两件事在 NAS 上必须分开。程序可以被覆盖重装，数据不行。

## 范围

- `server/src/static_files.rs` —— 新增 `data_dir()`，与 `app_dir()` 分离
- `server/src/database.rs` —— `get_db_path()` / `ensure_config_dir()` 改走 `data_dir()`
- `ops/setup.sh`、`ops/re-sourcer.service` —— **本卡明确允许修改**（project.md 的禁令在此放行）
- `docs/` —— 新增或更新部署说明
- **明确不做的**：不碰 web / iOS / E-ink；不改任何 HTTP 接口

## 实现方向

1. `data_dir()` 的解析优先级：
   `RESOURCER_DATA_DIR` 环境变量 → 配置文件指定 → 回退到 `app_dir()`（保持现有行为，向后兼容）
2. **自动迁移**：启动时若 `data_dir` 下没有 `sqlite/data.db`，而 `app_dir` 下有，
   则把 `sqlite/` 和 `config/` 整体搬过去，并在日志里明确写出搬了什么。绝不能悄悄新建空库。
3. **自动备份**：每次启动 + 每 N 小时，把 `data.db` 备份到 `data_dir/backups/data-<时间戳>.db`，
   保留最近若干份。用 SQLite 的 `VACUUM INTO` 或 backup API，**不要直接 cp**（WAL 模式下 cp 会拿到不一致的快照）。
4. `setup.sh` 询问/接受一个持久化目录（群晖 `/volume1/...`、QNAP `/share/...`），
   写进 systemd 的 `Environment=RESOURCER_DATA_DIR=...`。默认值要安全，不能仍然指回 `/opt`。

## Acceptance Criteria

- [ ] AC1: `RESOURCER_DATA_DIR=/tmp/rs-test-a cargo run` 启动后，`/tmp/rs-test-a/sqlite/data.db` 被创建
- [ ] AC2: 把旧数据放在 exe 同级目录、`data_dir` 指向空目录启动 → 旧的 `sqlite/` 和 `config/` 被迁移过去，日志有记录，**数据条数一致**（迁移前后各查一次同一张表比对）
- [ ] AC3: 启动后 `data_dir/backups/` 下出现备份文件，且该备份能被 `sqlite3` 正常打开、表结构完整
- [ ] AC4: 不设 `RESOURCER_DATA_DIR` 时行为与改动前一致（向后兼容，老用户升级不丢数据）
- [ ] AC5: `ops/re-sourcer.service` 与 `ops/setup.sh` 中不再把数据写进 `/opt`；`grep -rn '"/opt' server/src` 无新增命中
- [ ] AC6: `./.ai/guard.sh` 通过
