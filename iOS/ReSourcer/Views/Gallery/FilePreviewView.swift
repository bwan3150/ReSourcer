//
//  FilePreviewView.swift
//  ReSourcer
//
//  文件预览页面 - 支持图片缩放、视频播放、非媒体文件展示
//

import SwiftUI
import AVKit

// MARK: - FilePreviewView

/// 全屏文件预览视图
struct FilePreviewView: View {

    // MARK: - Properties

    let apiService: APIService

    @Environment(\.dismiss) private var dismiss

    // 文件列表与索引
    @State private var currentFiles: [FileInfo]
    @State private var currentIndex: Int

    // 控制栏
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    // 文件信息面板
    @State private var showInfoSheet = false

    // 重命名
    @State private var showRenameAlert = false
    @State private var renameText = ""

    // 移动
    @State private var showMoveSheet = false
    @State private var targetFolders: [FolderInfo] = []
    @State private var sourceFolder = ""

    // 操作状态
    @State private var isOperating = false

    // MARK: - Init

    init(apiService: APIService, files: [FileInfo], initialIndex: Int) {
        self.apiService = apiService
        _currentFiles = State(initialValue: files)
        _currentIndex = State(initialValue: min(initialIndex, files.count - 1))
    }

    // MARK: - Computed

    private var currentFile: FileInfo {
        currentFiles[currentIndex]
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // 黑色背景
            Color.black.ignoresSafeArea()

            // 主内容 - 左右滑动切换
            TabView(selection: $currentIndex) {
                ForEach(Array(currentFiles.enumerated()), id: \.element.id) { index, file in
                    fileContentView(for: file)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // 控制层
            if showControls {
                VStack {
                    topBar
                    Spacer()
                    if !currentFile.isVideo {
                        bottomControls
                    }
                }
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showControls)
        .animation(AppTheme.Animation.standard, value: showControls)
        .onChange(of: currentIndex) { _, _ in
            scheduleAutoHide()
        }
        .onAppear { scheduleAutoHide() }
        .onDisappear { hideControlsTask?.cancel() }
        // 文件信息面板
        .glassBottomSheet(isPresented: $showInfoSheet, title: "文件信息") {
            fileInfoContent
        }
        // 重命名弹窗
        .alert("重命名", isPresented: $showRenameAlert) {
            TextField("新文件名", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("确认") {
                Task { await performRename() }
            }
        } message: {
            Text("输入新的文件名（不含扩展名）")
        }
        // 移动面板
        .glassBottomSheet(isPresented: $showMoveSheet, title: "移动到") {
            moveSheetContent
        }
    }

    // MARK: - 文件内容路由

    @ViewBuilder
    private func fileContentView(for file: FileInfo) -> some View {
        switch file.fileType {
        case .image, .gif:
            ImagePreviewContent(
                file: file,
                apiService: apiService,
                onTap: { toggleControls() }
            )
        case .video:
            VideoPreviewContent(
                file: file,
                apiService: apiService,
                showControls: $showControls,
                onPrevious: currentIndex > 0 ? { withAnimation { currentIndex -= 1 } } : nil,
                onNext: currentIndex < currentFiles.count - 1 ? { withAnimation { currentIndex += 1 } } : nil
            )
        case .other:
            OtherFilePreviewContent(
                file: file,
                onTap: { toggleControls() }
            )
        }
    }

    // MARK: - 顶部浮动栏

    private var topBar: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // 返回按钮
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            // 文件名 + 计数
            VStack(spacing: 2) {
                Text(currentFile.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(currentIndex + 1) / \(currentFiles.count)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: 200)

            Spacer()

            // 信息按钮
            Button {
                showInfoSheet = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.sm)
    }

    // MARK: - 底部导航按钮

    private var bottomControls: some View {
        HStack {
            // 上一个
            Button {
                withAnimation { currentIndex = max(0, currentIndex - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .opacity(currentIndex > 0 ? 1.0 : 0.3)
            .disabled(currentIndex <= 0)

            Spacer()

            // 下一个
            Button {
                withAnimation { currentIndex = min(currentFiles.count - 1, currentIndex + 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .opacity(currentIndex < currentFiles.count - 1 ? 1.0 : 0.3)
            .disabled(currentIndex >= currentFiles.count - 1)
        }
        .padding(.horizontal, AppTheme.Spacing.xxl)
        .padding(.bottom, AppTheme.Spacing.xxl)
    }

    // MARK: - 文件信息面板内容

    private var fileInfoContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            infoRow("文件名", value: currentFile.name)
            infoRow("类型", value: currentFile.extension.uppercased())
            infoRow("大小", value: currentFile.formattedSize)
            infoRow("修改时间", value: currentFile.modified)

            if let width = currentFile.width, let height = currentFile.height {
                infoRow("分辨率", value: "\(width) × \(height)")
            }
            if let duration = currentFile.formattedDuration {
                infoRow("时长", value: duration)
            }

            // 操作按钮
            HStack(spacing: AppTheme.Spacing.md) {
                GlassButton("重命名", icon: "pencil", style: .secondary, size: .medium) {
                    showInfoSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        renameText = currentFile.baseName
                        showRenameAlert = true
                    }
                }
                .frame(maxWidth: .infinity)

                GlassButton("移动", icon: "folder", style: .secondary, size: .medium) {
                    showInfoSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        Task { await loadFolders() }
                        showMoveSheet = true
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, AppTheme.Spacing.sm)
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 移动面板内容

    private var moveSheetContent: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if targetFolders.isEmpty {
                GlassEmptyView(icon: "folder", title: "暂无可用文件夹")
                    .padding(.vertical, AppTheme.Spacing.xl)
            } else {
                ForEach(targetFolders) { folder in
                    Button {
                        Task { await performMove(to: folder) }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: "folder.fill")
                                .font(.title3)
                                .foregroundStyle(.yellow)
                            Text(folder.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(folder.fileCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(AppTheme.Spacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }

    // MARK: - 控制栏显示/隐藏

    private func toggleControls() {
        withAnimation(AppTheme.Animation.standard) {
            showControls.toggle()
        }
        if showControls {
            scheduleAutoHide()
        }
    }

    private func scheduleAutoHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(AppTheme.Animation.standard) {
                    showControls = false
                }
            }
        }
    }

    // MARK: - 文件操作

    private func loadFolders() async {
        do {
            let configState = try await apiService.config.getConfigState()
            sourceFolder = configState.sourceFolder
            targetFolders = try await apiService.folder.getSubfolders(in: sourceFolder)
                .filter { !$0.hidden }
        } catch {
            GlassAlertManager.shared.showError("加载文件夹失败", message: error.localizedDescription)
        }
    }

    private func performRename() async {
        let file = currentFile
        let newName = renameText + file.extension
        guard !renameText.isEmpty else { return }

        isOperating = true
        do {
            _ = try await apiService.file.renameFile(at: file.path, to: newName)
            GlassAlertManager.shared.showSuccess("重命名成功")
            handlePostOperation()
        } catch {
            GlassAlertManager.shared.showError("重命名失败", message: error.localizedDescription)
        }
        isOperating = false
    }

    private func performMove(to folder: FolderInfo) async {
        let file = currentFile
        isOperating = true
        do {
            let targetPath = sourceFolder + "/" + folder.name
            _ = try await apiService.file.moveFile(at: file.path, to: targetPath)
            showMoveSheet = false
            GlassAlertManager.shared.showSuccess("已移动到 \(folder.name)")
            handlePostOperation()
        } catch {
            GlassAlertManager.shared.showError("移动失败", message: error.localizedDescription)
        }
        isOperating = false
    }

    /// 操作完成后的导航逻辑
    private func handlePostOperation() {
        currentFiles.remove(at: currentIndex)
        if currentFiles.isEmpty {
            dismiss()
        } else if currentIndex >= currentFiles.count {
            currentIndex = currentFiles.count - 1
        }
    }
}

// MARK: - ImagePreviewContent

/// 图片/GIF 预览（支持双指缩放）
struct ImagePreviewContent: View {

    let file: FileInfo
    let apiService: APIService
    let onTap: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        let contentURL = apiService.preview.getContentURL(
            for: file.path,
            baseURL: apiService.baseURL,
            apiKey: apiService.apiKey
        )

        GeometryReader { geometry in
            AsyncImage(url: contentURL) { phase in
                switch phase {
                case .empty:
                    // 加载中
                    ZStack {
                        // 先显示缩略图占位
                        AsyncImage(
                            url: apiService.preview.getThumbnailURL(
                                for: file.path,
                                size: 300,
                                baseURL: apiService.baseURL,
                                apiKey: apiService.apiKey
                            )
                        ) { thumbPhase in
                            if case .success(let thumb) = thumbPhase {
                                thumb
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .blur(radius: 8)
                            }
                        }

                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    }

                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(pinchGesture)
                        .gesture(scale > 1.0 ? dragGesture : nil)
                        .onTapGesture(count: 2) { resetZoom() }
                        .onTapGesture(count: 1, perform: onTap)

                case .failure:
                    VStack(spacing: AppTheme.Spacing.lg) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("图片加载失败")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)

                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - 缩放手势

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastScale * value.magnification
                scale = min(max(newScale, 0.5), 4.0)
            }
            .onEnded { _ in
                lastScale = scale
                // 如果缩放过小，弹回 1.0
                if scale < 1.0 {
                    withAnimation(AppTheme.Animation.spring) {
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    // MARK: - 拖动手势（仅放大时）

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func resetZoom() {
        withAnimation(AppTheme.Animation.spring) {
            scale = scale > 1.0 ? 1.0 : 2.0
            lastScale = scale
            offset = .zero
            lastOffset = .zero
        }
    }
}

// MARK: - VideoPreviewContent

/// 视频播放预览
struct VideoPreviewContent: View {

    let file: FileInfo
    let apiService: APIService
    @Binding var showControls: Bool
    let onPrevious: (() -> Void)?
    let onNext: (() -> Void)?

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1
    @State private var timeObserver: Any?
    @State private var hideTimer: Task<Void, Never>?

    var body: some View {
        ZStack {
            // 视频播放器
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture { toggleVideoControls() }
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }

            // 自定义控制层
            if showControls {
                videoControlsOverlay
                    .transition(.opacity)
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { cleanupPlayer() }
    }

    // MARK: - 视频控制层

    private var videoControlsOverlay: some View {
        VStack {
            Spacer()

            // 中央播放/暂停
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            // 底部控制栏
            VStack(spacing: AppTheme.Spacing.md) {
                // 进度条
                Slider(value: $currentTime, in: 0...max(duration, 0.1)) { editing in
                    if !editing {
                        seekTo(currentTime)
                    }
                }
                .tint(.white)

                // 时间 + 导航
                HStack {
                    Text(formatTime(currentTime))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.8))

                    Spacer()

                    // 上一个/下一个
                    HStack(spacing: AppTheme.Spacing.xl) {
                        if let onPrevious = onPrevious {
                            Button {
                                cleanupPlayer()
                                onPrevious()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                            }
                            .glassEffect(.regular.interactive(), in: .circle)
                        }

                        if let onNext = onNext {
                            Button {
                                cleanupPlayer()
                                onNext()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                            }
                            .glassEffect(.regular.interactive(), in: .circle)
                        }
                    }

                    Spacer()

                    Text(formatTime(duration))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
    }

    // MARK: - 播放器管理

    private func setupPlayer() {
        guard let url = apiService.preview.getContentURL(
            for: file.path,
            baseURL: apiService.baseURL,
            apiKey: apiService.apiKey
        ) else { return }

        let avPlayer = AVPlayer(url: url)
        player = avPlayer

        // 监听时间
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
            if let item = avPlayer.currentItem {
                let dur = item.duration.seconds
                if dur.isFinite && dur > 0 {
                    duration = dur
                }
            }
        }

        // 监听播放状态
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            isPlaying = false
            avPlayer.seek(to: .zero)
        }

        avPlayer.play()
        isPlaying = true
        scheduleHideControls()
    }

    private func cleanupPlayer() {
        hideTimer?.cancel()
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
        timeObserver = nil
    }

    private func togglePlayback() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            hideTimer?.cancel()
        } else {
            player.play()
            scheduleHideControls()
        }
        isPlaying.toggle()
    }

    private func seekTo(_ time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }

    private func toggleVideoControls() {
        withAnimation(AppTheme.Animation.standard) {
            showControls.toggle()
        }
        if showControls && isPlaying {
            scheduleHideControls()
        }
    }

    private func scheduleHideControls() {
        hideTimer?.cancel()
        hideTimer = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if isPlaying {
                    withAnimation(AppTheme.Animation.standard) {
                        showControls = false
                    }
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - OtherFilePreviewContent

/// 非媒体文件展示
struct OtherFilePreviewContent: View {

    let file: FileInfo
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            // 文件图标
            Image(systemName: fileIconName)
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.6))

            // 文件名
            Text(file.name)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, AppTheme.Spacing.xxl)

            // 扩展名标签
            Text(file.extension.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.xs)
                .glassEffect(.regular, in: .capsule)

            // 文件大小
            Text(file.formattedSize)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    /// 根据扩展名返回 SF Symbol 图标
    private var fileIconName: String {
        let ext = file.extension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch ext {
        case "pdf":
            return "doc.fill"
        case "zip", "rar", "7z", "tar", "gz":
            return "doc.zipper"
        case "mp3", "wav", "aac", "flac", "m4a", "ogg":
            return "music.note"
        case "txt", "md", "rtf":
            return "doc.text"
        case "json", "xml", "yaml", "yml":
            return "curlybraces"
        case "py", "js", "ts", "swift", "rs", "go", "java", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "html", "css":
            return "globe"
        case "xls", "xlsx", "csv":
            return "tablecells"
        case "ppt", "pptx", "key":
            return "rectangle.fill.on.rectangle.fill"
        case "doc", "docx", "pages":
            return "doc.richtext"
        default:
            return "doc.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    let server = Server(name: "Test", baseURL: "http://localhost:1234", apiKey: "test")
    if let api = APIService.create(for: server) {
        FilePreviewView(
            apiService: api,
            files: [],
            initialIndex: 0
        )
    }
}
