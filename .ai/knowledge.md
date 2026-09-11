# 项目知识库

> 每个 Agent 都是全新上下文 —— 不写下来的坑，下一个会原样再踩一遍。
> 本文件由 Orchestrator 从各 Agent 的 `learnings` 字段汇总，Reviewer 定期去重压缩。
> **Agent 不要直接编辑本文件**（Reviewer 除外），把经验写进 outbox 的 `learnings` 里。

## 稳定模式（长期有效，Reviewer 维护）

<例：新增 server 模块必须在 main.rs 里挂载 routes，否则接口 404 但编译通过>

## 流水（自动追加，Reviewer 定期合并进上面）
- server 模块是四件套 `mod.rs`/`models.rs`/`storage.rs`/`handlers.rs`，新模块必须在 `main.rs` 挂载 routes，否则接口 404 但编译通过
- `.ai/guard.sh` 里每个 check 都跑在子 shell 里；写 `cd web && ...` 不会污染后续检查（曾因此让所有检查在错误目录下跑）
- 超阈文件的行数基线在 `.ai/baseline/linecount.txt`，只许变短。要加功能先拆文件
