# Idea Inbox

> 随手记，不打断当前任务。Reviewer 会定期整理成 backlog 里的合格任务卡。
> 写不出 Acceptance Criteria 的想法，会一直留在这里。

## 存量技术债（guard 棘轮已收编，新增会被拦；存量待还）

- `web/src/views/SettingsView.vue` 有 3 处裸 `fetch(`（611 检查更新、664/677 探测 server health），
  应收进 `web/src/api/`。基线：`.ai/baseline/bare-fetch.txt`
- 17 个文件超过 500 行，最长的三个：
  `FilePreviewView.swift` 2262 / `GalleryView.swift`(iOS) 1869 / `ClassifierView.swift` 1195。
  基线：`.ai/baseline/linecount.txt`。RS-003 / RS-004 会被迫先拆 FilePreviewView，
  拆完记得把基线刷新到更小的数字（只许变短）。

## 想到但还没写成任务卡的

<随手往这里加。Reviewer 会定期整理成 backlog 里的合格任务卡；写不出 AC 的会一直留在这里。>
