# 项目知识库

> 每个 Agent 都是全新上下文 —— 不写下来的坑，下一个会原样再踩一遍。
> 本文件由 Orchestrator 从各 Agent 的 `learnings` 字段汇总，Reviewer 定期去重压缩。
> **Agent 不要直接编辑本文件**（Reviewer 除外），把经验写进 outbox 的 `learnings` 里。

## 项目结构

- server 模块是四件套 `mod.rs`/`models.rs`/`storage.rs`/`handlers.rs`。**新模块必须在 `main.rs` 挂载 routes**，
  否则接口 404 但编译通过 —— 这个组合最容易误判成"代码没生效"。
- 实际路由与直觉不同，**写 API 测试前先读 mod.rs 不要猜**：目录浏览是 `POST /api/browser/browse`
  （不是 `GET /list`），配置保存是 `POST /api/config/save`，源文件夹是 `/api/config/sources/add`。
- 必填参数看 `models.rs` 的 Query struct 里哪些字段不是 `Option`。
  例：`GET /api/playlist` 要 uuid + folder_path + mode 三个，少给就是 400，**这是既有契约不是回归**。
- server 是纯二进制 crate（Cargo.toml 无 `[lib]`），`server/tests/` 下的集成测试 import 不到 bin crate 里的函数。
  内部纯逻辑要写 Rust 单测只能就地 `#[cfg(test)]`；Tester 不改 `src/` 的前提下这类逻辑只能黑盒验。
- 超阈文件的行数基线在 `.ai/baseline/linecount.txt`，**只许变短**。要加功能先拆文件，不要刷基线。

## 发布与部署

- **仓库里有两条发版线：`server-v*` 和 `web-v*`。任何地方都不准用 `/releases/latest`** ——
  它只给全仓库最新的那条，两条线会互相抢。实际踩过三处：服务端自更新、`ops/setup.sh` 的
  `get_latest_version`、以及遗留 Dockerfile，症状都是"在 release 里找不到本平台产物"。
  正确做法是列出 releases 再按 tag 前缀过滤。
- `app.json` 是数据文件，存在就不会被覆盖。版本号这类"由程序决定"的字段必须在启动时对账
  （`reconcile_app_json()`），否则用安装脚本升级二进制后它一直是旧值，关于页显示错版本、
  自更新还一直提示有新版。
- 服务端托管静态文件后，**鉴权中间件会把登录页一起拦成 401**，用户永远拿不到 API Key。
  非 `/api` 路径必须放行。
- 改了 `data_dir()` 下的目录归属（比如 `tools/`），**要同步改 `ops/setup.sh` 的下载落点**。
  全新安装没有旧数据库，迁移逻辑不触发，工具会被留在程序目录里，表现为"服务端找不到 ffmpeg"。
- 测试目录迁移逻辑会**真的把本地开发数据搬走**（sqlite/config/credentials/tools）。
  跑之前想好怎么搬回来。

## 外部工具

- **yt-dlp 是 PyInstaller 单文件包，每次运行都要自解压**：`--version` 实测 7~10 秒（CPU 只占 10%）。
  不要在请求路径里直接调，版本号要缓存（按二进制 mtime 失效）。
- **子进程的 stderr 必须自己打进日志**。yt-dlp 的报错只在 stderr，不打日志的话服务端日志里
  一行线索都没有，排障只能手动复现。
- X（Twitter）**公开内容不需要任何凭证**；只有受保护账号和敏感内容才要，而且除了
  `auth_token` + `ct0` 之外，**那个账号还必须自己开了「显示敏感内容」**，否则 cookies 再对也拿不到。
  `--extractor-args twitter:api=syndication` 对敏感内容没用（实测三个接口都报 "No video could be found"）。
- yt-dlp 的 `--cookies` 只认 Netscape 格式（7 个字段用制表符分隔）。网页输入框里打不出制表符，
  所以服务端接受 `auth_token` / `ct0` 裸值自己拼。

## 前端

- **Vue SFC 里模板在 `<script>` 之前**。扫"未使用的 import"必须扫整份文件；只扫 import 之后的内容
  会把模板里用着的组件判成未使用。而且**删错了构建不报错** —— Vue 对未注册组件只在运行时告警。
- 组件里不准裸 `fetch(`/`axios.`（guard 的 no-bare-fetch 棘轮）。要从组件里搬走 HTTP 调用时，
  记得它可能在 `.ai/baseline/bare-fetch.txt` 的豁免名单里 —— 搬进新文件会变成新违规，
  正确做法是下沉到 `web/src/api/`，顺带把原文件从名单里摘掉。

## 本地环境与测试

- **server 硬编码 bind `0.0.0.0:1234`，同一时刻只能起一个实例。** 连续跑多个场景必须串行并确认
  上一个已退出，否则第二个静默 AddrInUse 退出、而端口上仍是上一个实例在应答 ——
  极易得出"测的是新配置"的假结论（真踩过）。
- debug 版冷启动（新 `RESOURCER_DIR`）到 `/api/health` 可达要 16~34 秒，同目录第二次只要 1 秒。
  等待循环给到 45 秒，短了会拿到一串 HTTP 000 然后误判成接口全挂。
- Bash 工具里用 `&` 起的后台 server 在该次调用结束后不保证存活。要跨调用留着服务用
  `nohup` + `disown`，或者把"起服务 + 测 + 杀"写在同一次调用里。
- macOS 路径会被规范化（`/tmp` → `/private/tmp`）。拿 API 传进去的路径去 sqlite 里做精确匹配会查不到，
  要用 `LIKE '%/子目录名'` 或先规范化。
- 验收交互式安装脚本不必真的装：用 `sed -n '/^函数名() {/,/^}/p'` 把目标函数抽出来配桩函数单跑即可；
  "直接回车走默认值"这条路用 `script -q /dev/null` 配空 stdin 能真实复现。
- 造跨文件系统场景验 `fs::rename` 失败分支：`hdiutil attach -nomount ram://40960` 拿到 `/dev/diskN`，
  再 `diskutil eraseVolume HFS+ <名字> <dev>`。注意 hdiutil 输出带尾随空白，要 `awk '{print $1}'`。

## shell 陷阱

- `.ai/guard.sh` 里每个 check 跑在子 shell，写 `cd web && ...` 不会污染后续检查。
- macOS 自带 **bash 3.2 没有 `mapfile`/`readarray`**，用 `arr=( $(cmd) )` 或 `while read`，
  否则脚本中途以 unbound variable 崩掉、留下没被 kill 的 server。
- bash 3.2 里 `"$i："` 这种变量后紧跟全角字符会把字节切坏，拼中文注释用 `${i}` 加空格隔开。
- 同一个 shell 里 `&` 起 server 再 `&` 起一批 curl，然后跑裸 `wait` 会连 server 一起等、永不返回。
  要 `wait $curl_pids` 指定 pid。
- `hostname -I` 在部分 NAS 上**成功返回空串**而不是报错，`||` 接不住，要显式判空。

## iOS 自动化（tke / WDA）

- **tke 与自己直连 WDA 的调用必须串行**。并发打 WDA(8150) 会让 tke 判定它卡死并重启，
  被测 app 被挤到后台、会话 ID 全换。
- WDA 的 `/wda/dragfromtoforduration` 是"长按 duration 秒再瞬移"，SwiftUI `DragGesture` 只收到一跳，
  测不出拖动过程。要慢速插值拖动用 `POST /session/:id/actions` 的 W3C pointer actions
  （见 `.ai/reports/RS-003/wda-drag.sh`）。tke 的 `滑动` 在模拟器上也是瞬移，只能验最终结果。
- tke 没有 pinch/双击指令，直接打 WDA：`POST /wda/pinch {scale, velocity}`、`POST /wda/doubleTap {x,y}`。
  **坐标是 pt，tke 元素表给的是 px，要除以 3**（iPhone 17 Pro 是 402x874）。
  拖动过程连拍用 `xcrun simctl io <UDID> screenshot`，不经过 WDA、不会和 tke 打架。
- `LongPressGesture(maximumDistance:)` 挂在会被 `.offset()` 跟手位移的视图上时，容差在局部坐标系里量、
  会被内容位移抵消，慢速平移照样触发。验位移容差要用"慢速 pointerMove 再 pause"，
  快速大幅拖动测不出来。
- 做"移动后停住"这类**负向断言一定要跑对照组**（同脚本原地按住），否则 stayed 可能只是会话失效的假阴性。
- 预览页控制栏 10 秒自动隐藏；隐藏后点返回/底部按钮会点空并把控制栏切出来。
  每次读时间前先单击画面中部叫出控制栏再 refresh。
- 预览页"上一张/下一张"的顺序由 server 播放列表决定，**不是 Gallery 网格顺序**。
  写翻页断言前先长按播放模式按钮看 popover 里的实际顺序。
- 放大是否生效不用读元素表：纯色测试图 1x 时只有中间一条色带，2.5x 后整屏都是该颜色，
  截图缩到 500px 一眼可辨。
- 造测试素材用 ffmpeg `lavfi testsrc`（自带走秒计数器，seek 后画面里直接读得到秒数）；
  图片用 `lavfi color=` 纯色。本机 ffmpeg 没编 drawtext 滤镜。
- `xcodebuild -destination 'generic/platform=iOS Simulator'` 在 arm64 Mac 上因
  libclang_rt.iossim 缺 x86_64 slice 必失败，与代码无关。验编译用 `-destination 'id=<模拟器UDID>'`。
- 换新 `RESOURCER_DIR` 时把旧的 `config/secret.json` 拷过去，模拟器里的 app 就不用重新配服务器。
- tke 的 `等待` 参数不接受小数（`1.5s` 报错），用整数秒。
