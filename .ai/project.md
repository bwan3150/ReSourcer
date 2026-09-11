# ReSourcer — 项目长期规则

## 项目目标

本地创作素材管理中心：从 YouTube / Twitter / Pixiv 等下载素材 → 分类 → 浏览。
服务端常跑在 **NAS** 上，浏览端是局域网内的 web / iOS / E-ink 设备。

## 四端与目录

| 端 | 技术 | 目录 | 说明 |
|---|---|---|---|
| server | Rust + actix-web + rusqlite | `server/` | 唯一数据源，跑在 NAS |
| web | Vue 3 + Vite + Tailwind/daisyUI | `web/` | 局域网浏览器访问 |
| iOS | SwiftUI | `iOS/ReSourcer/` | 手机端 |
| E-ink | Kotlin/Android | `E-ink/` | 墨水屏设备 |

## 架构原则

**server**
- 每个功能域一个模块，固定四件套：`mod.rs`(只登记 routes) / `models.rs` / `storage.rs`(SQL) / `handlers.rs`(HTTP)。
  参照 `server/src/playlist/`，不要把 SQL 写进 handlers。
- 所有表在 `server/src/database.rs` 里 `CREATE TABLE IF NOT EXISTS` 建，不引入迁移框架。
- 数据库连接一律走 `database::get_connection()`（已配好 WAL + busy_timeout），不要自己 `Connection::open`。
- 路径一律走 `static_files::app_dir()` 派生，**不准硬编码 `/opt` 之类的绝对路径**。

**web**
- HTTP 请求一律走 `web/src/api/*.js`，组件里不准出现裸 `fetch(` 或直接 `axios.`。
- 可复用逻辑放 `web/src/composables/`。
- 用户可见文案走 `web/src/i18n/`（en + zh 都要加），不准硬编码中文/英文字符串。

**iOS**
- 网络走 `Services/APIService.swift` 等 Service 层，View 里不准直接发请求。
- 视觉组件复用 `Components/Glass*`，主题色走 `Theme/AppTheme.swift`。

**跨端**
- 改动任何 HTTP 接口，**必须同步 `docs/API.md`**；改动表结构，**必须同步 `docs/database.md`**。
- server 加了接口，不代表 web/iOS 要同时跟进 —— 按任务卡的范围来，不要顺手改别的端。

## 禁止事项

- ❌ 硬编码绝对路径、IP、端口、密钥。密钥只从 `config/secret.json` 读。
- ❌ 引入新的重量级依赖（新 crate / npm 包 / SPM 包）。确实需要 → 写进 `.ai/inbox.md` 说明理由，不要自己装。
- ❌ 修改 `ops/` 下的部署配置，除非任务卡明确要求。
- ❌ 让已经超长的文件继续变长（见下）。
- ❌ 改 `ci.sh`（发版流程）。

## 超长文件：只许变短

`iOS/.../FilePreviewView.swift` 已经 **2200+ 行**，`server/src/**/storage.rs` 也有几百行的。
guard 里的 `linecount` 用的是**棘轮基线**：超阈文件记住当前行数，**只许减不许增**。

> 要往这类文件加功能，**先把要加的部分拆成新文件**（按"职责/渲染对象"拆，不要按行数硬切），
> 再在原文件里引用。这不是洁癖 —— 越长越没人敢拆，越没人拆越长。
>
> 基线在 `.ai/baseline/linecount.txt`。**它不是用来让守卫闭嘴的**，不准为了通过而刷新基线。

## 测试要求

| 层 | 怎么做 |
|---|---|
| 编译 | `cargo check --manifest-path server/Cargo.toml`；web `cd web && npm run build` |
| 单元测试 | `cargo test --manifest-path server/Cargo.toml` |
| 启动 | `RESOURCER_DIR=<临时目录> cargo run --manifest-path server/Cargo.toml`，默认端口见 `server/src/main.rs` |
| API 测试 | 起服务后用 curl/脚本打真实接口，检查状态码 + JSON 字段；**要覆盖重启后数据是否还在** |
| web UI | `cd web && npm run dev` → http://localhost:5173 ，用 `tke-ui-test` skill 操作真实浏览器 |
| iOS UI | 用 `tke-ui-test` skill 驱动 iOS 模拟器/真机，**手势类改动必须真机实测并留截图序列**，光编译通过不算数 |

**iOS 的手势改动不可能靠读代码验证**，Tester 必须真的把 app 跑起来操作。

## 相关文档（Reviewer 的判据）

- `docs/API.md` —— 接口约定
- `docs/database.md` —— 表结构
- `README.md` —— 对外功能说明与 To-do
