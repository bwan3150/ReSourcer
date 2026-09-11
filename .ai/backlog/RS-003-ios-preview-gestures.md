---
id: RS-003
type: feature
priority: 3
status: READY
attempt: 0
needs_human: false
created: 2026-09-11
---
# iOS 预览页：视频画面上左右拖动调进度，图片左右滑动切上/下一张

## 背景

现在 iOS 预览页调视频进度只能去够底部那条细进度条，单手拿手机时很难点准。
应该像主流播放器一样：**在视频画面任意位置左右拖动**就能 seek。
图片则应该能**左右滑动切换上一张/下一张**，而不是退出去再点下一个。

只做 **iOS**，web 端不需要改。

## 范围

- `iOS/ReSourcer/Views/Gallery/FilePreviewView.swift` —— 接入手势
- **新建文件**放手势逻辑（见下方硬约束）
- **明确不做的**：不碰 web / server / E-ink；不改现有进度条 UI 的样式；不动播放列表逻辑

## ⛔ 硬约束：不许让 FilePreviewView.swift 再变长

该文件**已经 2262 行**，guard 的 linecount 棘轮会拦住任何增长（基线 `.ai/baseline/linecount.txt`）。

> 把手势逻辑拆成独立文件，例如 `Views/Gallery/Gestures/SeekDragGesture.swift`、
> `Views/Gallery/Gestures/PageSwipeGesture.swift`，在 FilePreviewView 里只留调用。
> 按「职责」拆，不要为了凑行数硬切。**不准刷新棘轮基线来绕过。**

## 实现方向

现有手势（读代码确认后再动手）：
- 视频与图片区域都已有 `pinchGesture`、`onTapGesture(count:2)` 重置缩放、`onTapGesture(count:1)` 切换控制栏
- 平移拖动是 `.simultaneousGesture(scale > 1.0 ? dragGesture : nil)` —— **只在放大时启用**

所以 `scale == 1.0` 时水平方向是空闲的，正好接管：

- **视频 seek**：`scale == 1.0` 时水平拖动 → 按拖动距离换算时间偏移（相对当前位置，不是绝对定位），
  拖动中显示 HUD（目标时间 / 偏移量），松手才真正 `seek`。垂直方向不要抢（留给以后的亮度/音量）。
- **图片翻页**：`scale == 1.0` 时水平滑动超过阈值 → 上一张 / 下一张，复用现有播放列表/索引逻辑，
  到头时给出边界反馈而不是静默无响应。
- 放大状态（`scale > 1.0`）必须保持原有平移行为不变。

## Acceptance Criteria

> **这是手势改动，读代码和编译通过都不算验证。Tester 必须用 `tke-ui-test` 把 app 真的跑起来操作，并留截图序列。**

- [ ] AC1: Xcode 能编译通过（`xcodebuild -scheme ReSourcer -destination 'generic/platform=iOS Simulator' build` 或等效命令）
- [ ] AC2: 模拟器/真机上打开一个视频，在**画面中部**水平拖动 → 播放进度改变，拖动过程中有 HUD 提示目标时间
- [ ] AC3: 同一视频双指放大后拖动 → 仍是平移画面，**不会**误触发 seek
- [ ] AC4: 打开一张图片，左滑 → 显示下一张；右滑 → 回到上一张；与缩略图列表顺序一致
- [ ] AC5: 图片放大后拖动 → 仍是平移，不会误翻页
- [ ] AC6: 单击切换控制栏、双击重置缩放等原有交互未被破坏
- [ ] AC7: `./.ai/guard.sh` 通过，**其中 linecount 必须绿**（即 FilePreviewView.swift 没有变长）

## 备注

- 现有的 `onLongPressGesture` 挂在**工具栏按钮**上（文件名 Capsule → 快捷操作；播放模式按钮 → 播放列表），
  和媒体区域的手势不在同一视图，但改动时要回归验证它们仍然可用。
- RS-004 会在媒体区域加长按退出，两张卡会动同一片区域，注意手势之间不要互相吞掉。
