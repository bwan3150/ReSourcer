# HEIC / Live Photo / Orientation — 打回复测报告

> 分支：`cursor/heic-live-photo-55de`  
> 禁止 merge / release。  
> **known in-scope = 1**（见 §3：模拟器 Share Extension 无法用 Photos `PairedVideo` 闭环 MOV；不得把 companion 写成过关）

---

## 1. 大图居中（根因 + 前后对比）

### 根因 A（服务端缩略图）
HEIC tile grid 用 `coded_*`（如 1536×1024）xstack，**未 crop 到 ispe**（1200×900）。  
Orientation=6 旋转后底边黑边变成「左空右切」。

**修复**：`parse_heif_tile_grid` 只读 `[COMPONENT]`；xstack 后 `crop=display_w:display_h:crop_x:crop_y`；`THUMBNAIL_VERSION=4`。

| 证据 | BEFORE | AFTER |
|------|--------|-------|
| ffmpeg 拼合+转置 | L=64 R=0 asym=32 | L=0 R≈0 asym≈0 |
| `heic-thumb-before-after.png` | 左空右切 | 满幅绿顶红底居中 |
| API s1600 HEIC/JPG | — | 1200×1600 白卡 asym≤0.5 |

### 根因 B（Web MediaPlayer）
`max-h-full` + `w/h-auto` 在 Chrome 先按宽算出超高 intrinsic，再被 `overflow:hidden` **裁掉顶底**（绿/红条消失），全页截图含侧栏时还会被误读成「左空右切」。

**修复**：预览 `img`/`video` 改为 `absolute inset-0 w-full h-full object-contain`（盒铺满、像素 letterbox 居中）。HEIC 大图仍走 `thumbnail?size=1600`（`previewDisplayUrl`）。

| 证据（相对预览 pane，侧栏除外） | 结果 |
|------|------|
| `web-orient6-heic-preview.png` + `-annotated.png` | **ml=273 mr=269 asym=2.0** |
| `web-orient6-jpg-preview.png` + `-annotated.png` | **ml=273 mr=270 asym=1.5** |
| img client box | 1176×851（不再 1176×1568 溢裁） |

iOS：`Color.black` + overlay + `scaledToFit` + `frame(maxWidth/Height: .infinity)`；HEIC 走 tv=4 / size=1600 转正 JPEG。

---

## 2. 方向对照（构图 vs EXIF）

`IMG_LIVE` / `upload_orig` / `e2e-share-orig` 网格文字侧向：

1. 原片 Orientation=6；sensor 横放  
2. 应用 Orient → 竖幅；API tv=4 thumb 同朝向  
3. 网格卡 = 转正后的**正方形中心裁切** → 画面内文字仍可呈侧向构图  

⇒ **构图本身**，不是 thumb Orientation 仍错。

证据：`orient-proof-sensor-vs-thumb.png`  
对照：`orient6` 绿顶红底 + UP 在 API / Web（本轮）正向一致。

---

## 3. Share ← Photos 真分享

### 已证明
- UITest `PhotosShareLiveHEICUITests`：系统相册 → Share Sheet → ReSourcer  
- 服务端可收到 **HEIC**（`ftypheic` 魔数）  
- Provider：`public.jpeg|com.apple.live-photo|public.heic`（常无独立 movie UTI）  
- 代码路径：`enrichLivePhotoPairedVideos` → `PHAssetResource.pairedVideo`

### known = 1（未过关）
模拟器 Share Extension 上 `PHAuthorizationStatus` 常为 **denied(2)**（即便 `simctl privacy grant photos`）。  
因此 **无法依赖 Photos `PairedVideo` 交 MOV**。

此前用 App Group Content-ID **companion MOV** 可让 CI 绿，但根会话明确不接受。  
现已改为：**默认禁止 companion**；仅当主 App 写入 `e2e_allow_live_companion=1`（`E2E_ALLOW_LIVE_COMPANION=1`）时才启用，并在 `live-enrich-debug.log` 标注 `source=photos-pairedVideo|e2e-companion`。

**真机**应走 `photos-pairedVideo`（代码已就绪）；本轮模拟器 **不得**把 companion 写成 known=0。

### 自动化复现
```bash
# 环境变量必须 export 进 xcodebuild 进程（见 iOS/scripts/run-ui-tests.sh）
E2E_SERVER_URL=http://127.0.0.1:1234 \
E2E_API_KEY=… \
E2E_SOURCE_FOLDER=… \
E2E_SCREENSHOT_DIR=docs/screenshots/heic-live-photo \
ONLY_TESTING=ReSourcerUITests/PhotosShareLiveHEICUITests \
DESTINATION='platform=iOS Simulator,id=<UDID>' \
bash iOS/scripts/run-ui-tests.sh

# 若仅验证 HEIC、不接受 companion MOV：不要设 E2E_ALLOW_LIVE_COMPANION
# 真机 / 需 CI 回退时才：E2E_ALLOW_LIVE_COMPANION=1
```

截图：`share-photos-01` … `share-photos-07`（历史轮次；本轮以 enrich 日志 `source=` 为准）。

---

## 4. 其它

| 项 | 状态 |
|----|------|
| LIVE hold | `ios-live-photo-hold.png` + `ios-live-photo-hold.mp4`（居中预览上按住实况） |
| iOS orient6 HEIC/JPG | L=R=0 asym=0；见 `*-annotated.png` |
| Web MediaPlayer | HEIC→1600 thumb；`object-contain` 满盒；pane asym≤2 |

---

## 5. 媒体

覆盖：`media/heic-live-photo/` ↔ `docs/screenshots/heic-live-photo/` ↔ 本报告。
