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
- `2026-09-12` RS-002/tester — 2026-09-12 RS-002/tester — macOS 自带 bash 3.2 没有 mapfile/readarray，测试脚本要用 arr=( $(cmd) ) 或 while read；否则脚本会在中途以 unbound variable 崩掉、留下没被 kill 的 server。
- `2026-09-12` RS-002/tester — 2026-09-12 RS-002/tester — 在同一个 shell 里用 & 起 server 再用 & 起一批 curl 后跑裸 `wait`，会连 server 一起等、永远不返回。并发测试要 `wait $curl_pids` 指定 pid，或把 server 放到另一个进程组（nohup … & disown）再 wait。
- `2026-09-12` RS-002/tester — 2026-09-12 RS-002/tester — GET /api/playlist 的必填参数是 uuid + folder_path + mode 三个，只给 uuid 会 400，这不是回归。写回归脚本前先看 models.rs 的 Query struct 哪些字段不是 Option。
- `2026-09-12` RS-002/tester — 2026-09-12 RS-002/tester — 首次冷启动（新 RESOURCER_DIR）到 /api/health 可达约 34s，第二次同目录启动只要 1s；等待循环给 45s 够用。
- `2026-09-12` RS-003/tester — 2026-09-12 RS-003/tester — 在 tke 执行 steps 的同时并发直连 WebDriverAgent(端口 8150)发请求，tke 会判定 WDA 卡死并重启它，把被测 app 挤到后台、会话 ID 全换；tke 与自己的 WDA 调用必须串行。
- `2026-09-12` RS-003/tester — 2026-09-12 RS-003/tester — WDA 的 /wda/dragfromtoforduration 是『长按 duration 秒再瞬移』，SwiftUI DragGesture 只收到一跳，测不出拖动中的 HUD、甚至可能不触发 onChanged；要慢速插值拖动用 POST /session/:id/actions 的 W3C pointer actions（pointerMove 带 duration），脚本见 .ai/reports/RS-003/wda-drag.sh。tke 的 滑动 [.., .., 毫秒] 在 iOS 模拟器上也是瞬移，只能验最终结果。
- `2026-09-12` RS-003/tester — 2026-09-12 RS-003/tester — tke 没有 pinch/双击指令；模拟器上可直接打 WDA：POST /wda/pinch {scale, velocity}、POST /wda/doubleTap {x,y}（坐标是 pt，iPhone 17 Pro 是 402x874，tke 元素表给的是 px，除以 3）。拖动过程中的画面用 xcrun simctl io <UDID> screenshot 连拍，不经过 WDA、不会和 tke 打架。
- `2026-09-12` RS-003/tester — 2026-09-12 RS-003/tester — 视频预览页控制栏 10s 自动隐藏（LocalStorageService autoHideDelay 默认 10），隐藏后点顶部返回/底部按钮会点空并把控制栏切出来；每次读时间前先单击画面中部叫出控制栏再 refresh。
- `2026-09-12` RS-003/tester — 2026-09-12 RS-003/tester — 造测试视频用 ffmpeg lavfi testsrc（自带走秒计数器，seek 后画面里直接能读到秒数），本机 ffmpeg 没编 drawtext 滤镜；图片用 lavfi color= 纯色即可靠标题+颜色区分。
- `2026-09-12` RS-003/tester — 2026-09-12 RS-003/tester — `xcodebuild -destination 'generic/platform=iOS Simulator'` 在这台 arm64 Mac 上因 libclang_rt.iossim 缺 x86_64 slice 必失败，与代码无关（HEAD~1 同样失败）；验编译用 -destination 'id=<模拟器UDID>'。
