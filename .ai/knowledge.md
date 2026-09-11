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
- `2026-09-11` RS-001/tester — server 是纯二进制 crate（Cargo.toml 无 [lib]），server/tests/ 下的集成测试无法 import bin crate 里的函数。要给 server 内部纯逻辑写 Rust 单测，只能就地 #[cfg(test)] 或抽 lib target —— Tester 不改 src/ 的前提下，这类逻辑只能黑盒验。
- `2026-09-11` RS-001/tester — server 硬编码 bind 0.0.0.0:1234，同一时刻只能起一个实例。连续跑多个测试场景必须串行并确保上一个进程已退出，否则第二个静默 AddrInUse 退出、而端口上仍是上一个实例在服务，极易得出「测的是新配置」的假结论（本轮踩过：以为在测新实例，实际是上一个遗留进程在应答）。
- `2026-09-11` RS-001/tester — debug 版 server 从启动到 /api/health 可达要 16~17 秒（实测 33~34 次 0.5s 探测）。写 API 测试的等待循环要给到 30s 以上，短了会拿到一串 HTTP 000 然后误判成接口全挂。
- `2026-09-11` RS-001/tester — Bash 工具里用 `&` 起的后台 server 在该次调用结束后不保证存活；要跨调用留着服务，用 nohup + disown，或者把「起服务 + 测 + 杀」写在同一次调用里。
- `2026-09-11` RS-001/tester — macOS 上路径会被规范化：/tmp -> /private/tmp。拿 API 传进去的路径去 sqlite 里做 folder_path 精确匹配会查不到（本轮误报过一次 FAIL），要用 LIKE '%/子目录名' 或先规范化再比。
- `2026-09-11` RS-001/tester — 要在 macOS 上造「跨文件系统」场景验证 fs::rename 失败分支：hdiutil attach -nomount ram://40960 拿到 /dev/diskN，再 diskutil eraseVolume HFS+ <名字> <dev> 就会挂到 /Volumes/<名字>，用 df 确认两侧 Filesystem 列不同即可。注意 hdiutil 输出带尾随空白，要用 awk '{print $1}' 取设备名。
- `2026-09-11` RS-001/tester — 验收 ops 下的交互式安装脚本不必真的执行安装：用 sed -n '/^函数名() {/,/^}/p' 把目标函数抽出来、配上桩 info/warn 单独跑，就能覆盖各分支；交互式「直接回车走默认值」这条路用 script -q /dev/null 配合空 stdin 能真实复现。
- `2026-09-11` RS-001/tester — ReSourcer 的真实路由与直觉不同，写 API 测试前先看 mod.rs 而不要猜：目录浏览是 POST /api/browser/browse（不是 GET /list），播放队列是 GET /api/playlist 且必须带 uuid 查询参数（不带就是 400，属既有契约），配置保存是 POST /api/config/save、源文件夹是 /api/config/sources/add。
