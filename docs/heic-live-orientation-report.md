# HEIC 原样 / 实况配对 / 缩略图 Orientation — 四段报告（打回后重测）

**Draft PR：** https://github.com/bwan3150/ReSourcer/pull/30  
**分支：** `cursor/heic-live-photo-55de` → `main`  
**状态：** Draft（**禁止 merge / release**）  
**known in-scope = 0**

截图 / 录屏：
- Store：`/cursor/stores/self/media/heic-live-photo/`
- Repo：`docs/screenshots/heic-live-photo/`（已 push，MD5 全唯一）
- 本报告：Store `docs/heic-live-orientation-report.md` + 分支 `docs/heic-live-orientation-report.md`

---

## 1. 改了什么

### 上传保留 HEIC 原样 + 实况
- iOS `PhotoExporter` / `PhotoUploadView`：PHPicker `.current` + `PHAssetResource`；实况附带 `PairedVideo`。
- Share Extension：`loadFileRepresentation` 优先 `public.heic`；实况同 provider **双取**静帧 + 视频；禁止 `UIImage → jpegData`。
- Share 上传客户端探针（`ShareOriginalFormatUITests`）：服务端落盘 **HEIC + MOV**，同 stem，**同一 Content Identifier**，列表挂 `live_video_*`。

### 服务端实况配对 + Orientation
- 同目录同 stem → `live_video_uuid` / `live_video_path`；网格隐藏配对 MOV。
- 缩略图 `THUMBNAIL_VERSION = 3`：按 EXIF/HEIF Orientation **转正像素**；**不改原文件**。

### iOS 大图布局（打回项 1）
- **根因是布局，不是 Orientation 算错**：`GeometryReader` 默认 topLeading + `PHLivePhotoView` 无视 `contentMode` 导致偏裁。
- 修复：Image 明确宽高提议 + `scaledToFit`；实况按 `livePhoto.size` **算死 aspect-fit 外框**，ZStack 居中；像素测量确认上下 letterbox、满宽居中。

### LIVE 标记（打回项 2）
- 媒体层 `ignoresSafeArea` 使 `safeAreaPadding` 失效；改为 **窗口 `safeAreaInsets.top + 52`**（状态栏 + 顶栏按钮行之下）。
- 样式：`glassBackground(in: Capsule())`（原生 Liquid Glass）。证据：`ios-live-badge.png`。

### 测试素材（打回项 3）
- 禁止纯蓝。现用：带绿顶/红底/UP 箭头的 Orientation=6 HEIC+JPG；真机实况 `IMG_LIVE.HEIC`+`IMG_LIVE.MOV`（Content Identifier `950E444E-…`）。
- 对照：API 缩略图 / iOS 网格 / iOS 大图 / Web 大图。

---

## 2. 怎么验证

| 项 | 结果 |
|----|------|
| 素材 Content Identifier | HEIC+MOV 一致 `950E444E-D736-41CF-A4A2-472D76C20389` |
| API thumb orient6.* | 竖图；绿顶红底可读 |
| `HeicLivePhotoUITests` 4/4 | 网格；LIVE+按住不退出；orient6 HEIC/JPG |
| iOS 录屏 | `ios-live-photo-hold.mp4`（按住区间有帧差） |
| Share 上传探针 | `e2e-share-orig-*.heic` + `.mov`，MIME `image/heic`，配对成功 |
| Mac Release archive（最终 HEAD） | `generic/platform=iOS` **ARCHIVE SUCCEEDED**；包内含 `ShareExtension.appex`；arm64 sim Release **BUILD SUCCEEDED** |
| Web 预览 | HEIC 走 tv=3 大缩略图；LIVE 静帧+角标 |

关键证据（均在 `media/heic-live-photo/`，MD5 全唯一）：
- `ios-gallery-grid.png` / `ios-orient6-{heic,jpg}-preview.png`
- `ios-live-photo-hold.png` + `ios-live-photo-hold.mp4` + `ios-live-badge.png`
- `web-gallery-grid.png` / `web-orient6-*-preview.png` / `web-img-live-preview.png`
- `api-thumb-*.jpg` / `share-*.png` / `share-upload-result-grid.png`

E2E：`RESOURCER_DATA_DIR=/private/tmp/resourcer-heic-live-e2e/data`，源 `/private/tmp/resourcer-heic-live-e2e/src`，API `:1234`。

---

## 3. 未测 / 已知限制（非 in-scope 缺陷）

- **Share Extension ← Photos 系统分享 UI**：本机辅助功能无法完整点通 Share Sheet；已用 **同一 `ShareUploadClient` 路径**（Share Extension 所用上传客户端）上传真实 HEIC+MOV 并验证服务端格式与配对。代码路径：`ShareViewController` heic-first + 实况双取。若某系统版本 Share Sheet 只抛 JPEG，属系统限流，应用侧无法强行取 HEIC——可行替代：App 内相册上传（`PhotoExporter` / PairedVideo）。
- Web 不能原生解码 HEIC 原片；预览用转正 JPEG 缩略图属预期，下载仍是原 HEIC。
- 无 Content Identifier 的合成对：`PHLivePhoto.request` 失败时回退静帧+按住 MOV（本轮真机 CID 对已走原生 PHLivePhoto）。

**known in-scope = 0**

---

## 4. 禁止事项

- **禁止 merge**
- **禁止 release / 打 tag / 发版**
- 本 PR 保持 **draft**
