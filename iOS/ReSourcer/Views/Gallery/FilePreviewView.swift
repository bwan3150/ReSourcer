//
//  FilePreviewView.swift
//  ReSourcer
//
//  文件预览页面 - 支持图片缩放、视频播放、非媒体文件展示
//

import SwiftUI
import AVKit
import AVFoundation
import ImageIO
import Photos

// MARK: - PlaybackMode

/// 播放模式
enum PlaybackMode {
    /// 循环当前 — 视频循环播放，图片/其他文件停留不动
    case repeatCurrent
    /// 顺序播放 — 按文件列表顺序自动播放下一个
    case sequential
    /// 随机播放 — 随机跳到文件列表中的另一个文件
    case shuffle

    /// SF Symbol 图标名
    var iconName: String {
        switch self {
        case .repeatCurrent: return "repeat.1"
        case .sequential:    return "repeat"
        case .shuffle:       return "shuffle"
        }
    }

    /// 描述文字
    var label: String {
        switch self {
        case .repeatCurrent: return "循环当前"
        case .sequential:    return "顺序播放"
        case .shuffle:       return "随机播放"
        }
    }

    /// 切换到下一个模式
    var next: PlaybackMode {
        switch self {
        case .repeatCurrent: return .sequential
        case .sequential:    return .shuffle
        case .shuffle:       return .repeatCurrent
        }
    }
}

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

    // 视频播放状态
    @State private var isVideoPlaying = false

    // 播放模式
    @State private var playbackMode: PlaybackMode = .repeatCurrent
    @State private var autoAdvanceTask: Task<Void, Never>?

    // 操作状态
    @State private var isOperating = false

    // MARK: - Init

    init(apiService: APIService, files: [FileInfo], initialIndex: Int) {
        self.apiService = apiService
        _currentFiles = State(initialValue: files)
        _currentIndex = State(initialValue: min(initialIndex, files.count - 1))
    }

    // MARK: - Computed

    private var currentFile: FileInfo? {
        guard !currentFiles.isEmpty, currentIndex >= 0, currentIndex < currentFiles.count else { return nil }
        return currentFiles[currentIndex]
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // 黑色背景
            Color.black.ignoresSafeArea()

            // 直接显示当前文件（替代 TabView 避免索引跳跃）
            if let file = currentFile {
                fileContentView(for: file)
                    .id(file.id) // 用文件 id 确保移除后视图重建
                    .ignoresSafeArea()

                // 底部控制层
                if showControls {
                    VStack {
                        Spacer()
                        bottomControls
                    }
                    .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarVisibility(showControls ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                }
            }

            ToolbarItem(placement: .principal) {
                Button {
                    showInfoSheet = true
                } label: {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(currentFile?.name ?? "")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .buttonStyle(.plain)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(AppTheme.Animation.standard) {
                        playbackMode = playbackMode.next
                    }
                    startAutoAdvanceTimer()
                } label: {
                    Image(systemName: playbackMode.iconName)
                        .fontWeight(.semibold)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!showControls)
        .animation(AppTheme.Animation.standard, value: showControls)
        .onChange(of: currentIndex) { _, _ in
            scheduleAutoHide()
            startAutoAdvanceTimer()
        }
        .onAppear {
            scheduleAutoHide()
            startAutoAdvanceTimer()
        }
        .onDisappear {
            hideControlsTask?.cancel()
            cancelAutoAdvanceTimer()
        }
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
                isPlaying: $isVideoPlaying,
                showControls: $showControls,
                playbackMode: playbackMode,
                onVideoEnd: { advanceToNext() }
            )
        case .other:
            OtherFilePreviewContent(
                file: file,
                onTap: { toggleControls() }
            )
        }
    }

    // MARK: - 底部导航按钮

    private var bottomControls: some View {
        HStack {
            // 上一个
            Button {
                withAnimation { currentIndex = max(0, currentIndex - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.85))
                    .clipShape(Circle())
            }
            .opacity(currentIndex > 0 ? 1.0 : 0.3)
            .disabled(currentIndex <= 0)

            Spacer()

            // 视频播放/暂停按钮
            if currentFile?.isVideo == true {
                Button {
                    isVideoPlaying.toggle()
                } label: {
                    Image(systemName: isVideoPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.85))
                        .clipShape(Circle())
                }
            }

            Spacer()

            // 下一个
            Button {
                withAnimation { currentIndex = min(currentFiles.count - 1, currentIndex + 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.85))
                    .clipShape(Circle())
            }
            .opacity(currentIndex < currentFiles.count - 1 ? 1.0 : 0.3)
            .disabled(currentIndex >= currentFiles.count - 1)
        }
        .padding(.horizontal, AppTheme.Spacing.xxl)
        .padding(.bottom, AppTheme.Spacing.xxl)
    }

    // MARK: - 文件信息面板内容

    @ViewBuilder
    private var fileInfoContent: some View {
        if let file = currentFile {
            VStack(spacing: AppTheme.Spacing.lg) {
                infoRow("文件名", value: file.name)
                infoRow("位置", value: "\(currentIndex + 1) / \(currentFiles.count)")
                infoRow("类型", value: file.extension.uppercased())
                infoRow("大小", value: file.formattedSize)
                infoRow("修改时间", value: file.modified)

                if let width = file.width, let height = file.height {
                    infoRow("分辨率", value: "\(width) × \(height)")
                }
                if let duration = file.formattedDuration {
                    infoRow("时长", value: duration)
                }

                // 操作按钮
                HStack(spacing: AppTheme.Spacing.md) {
                    GlassButton("重命名", icon: "pencil", style: .secondary, size: .medium) {
                        showInfoSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            renameText = file.baseName
                            showRenameAlert = true
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GlassButton("移动", icon: "folder", style: .secondary, size: .medium) {
                        showInfoSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            Task { await self.loadFolders() }
                            showMoveSheet = true
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GlassButton("下载", icon: "arrow.down.circle", style: .secondary, size: .medium) {
                        showInfoSheet = false
                        saveFileToDevice(file)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, AppTheme.Spacing.sm)
            }
            .padding(.vertical, AppTheme.Spacing.md)
        }
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
                    let isSource = folder.name == URL(fileURLWithPath: sourceFolder).lastPathComponent
                    Button {
                        Task { await performMove(to: folder) }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: isSource ? "folder.fill.badge.gearshape" : "folder.fill")
                                .font(.title3)
                                .foregroundStyle(isSource ? .orange : .yellow)
                            Text(folder.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            if !isSource {
                                Text("\(folder.fileCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
        // 仅视频播放时自动隐藏（10秒），图片和其他文件始终显示控制栏
        guard currentFile?.isVideo == true else { return }
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(AppTheme.Animation.standard) {
                    showControls = false
                }
            }
        }
    }

    // MARK: - 播放模式逻辑

    /// 根据当前播放模式跳转到下一个文件
    private func advanceToNext() {
        switch playbackMode {
        case .repeatCurrent:
            break
        case .sequential:
            withAnimation {
                if currentIndex < currentFiles.count - 1 {
                    currentIndex += 1
                } else {
                    currentIndex = 0
                }
            }
        case .shuffle:
            guard currentFiles.count > 1 else { return }
            var nextIndex: Int
            repeat {
                nextIndex = Int.random(in: 0..<currentFiles.count)
            } while nextIndex == currentIndex
            withAnimation {
                currentIndex = nextIndex
            }
        }
    }

    /// 启动图片/其他文件的自动跳转定时器（8秒）
    private func startAutoAdvanceTimer() {
        cancelAutoAdvanceTimer()
        guard playbackMode != .repeatCurrent else { return }
        guard currentFile?.isVideo != true else { return }

        autoAdvanceTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            advanceToNext()
        }
    }

    /// 取消自动跳转定时器
    private func cancelAutoAdvanceTimer() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
    }

    // MARK: - 文件操作

    private func saveFileToDevice(_ file: FileInfo) {
        guard let contentURL = apiService.preview.getContentURL(
            for: file.path,
            baseURL: apiService.baseURL,
            apiKey: apiService.apiKey
        ) else {
            GlassAlertManager.shared.showError("无法获取文件地址")
            return
        }

        GlassAlertManager.shared.showQuickLoading()

        Task.detached {
            do {
                let (data, _) = try await URLSession.shared.data(from: contentURL)

                if file.fileType.isMedia {
                    // 检查相册权限
                    var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                    if status == .notDetermined {
                        status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                    }
                    guard status == .authorized else {
                        await MainActor.run {
                            GlassAlertManager.shared.hideQuickLoading()
                            GlassAlertManager.shared.showError("无法访问相册", message: "请在设置中允许访问相册")
                        }
                        return
                    }

                    // 通过 ObjC 包装器保存到相册
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        PhotoExporter.saveFile(toPhotos: data, fileName: file.name) { success, error in
                            if success {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: error ?? APIError.unknown("保存失败"))
                            }
                        }
                    }

                    await MainActor.run {
                        GlassAlertManager.shared.hideQuickLoading()
                        GlassAlertManager.shared.showSuccess("已保存到相册")
                    }
                } else {
                    // 非媒体文件：写入临时文件后弹出分享面板
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(file.name)
                    try data.write(to: tempURL)

                    await MainActor.run {
                        GlassAlertManager.shared.hideQuickLoading()

                        let activityVC = UIActivityViewController(
                            activityItems: [tempURL],
                            applicationActivities: nil
                        )
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootVC = windowScene.windows.first?.rootViewController {
                            activityVC.popoverPresentationController?.sourceView = rootVC.view
                            activityVC.popoverPresentationController?.sourceRect = CGRect(
                                x: rootVC.view.bounds.midX,
                                y: rootVC.view.bounds.midY,
                                width: 0, height: 0
                            )
                            activityVC.popoverPresentationController?.permittedArrowDirections = []
                            rootVC.present(activityVC, animated: true)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    GlassAlertManager.shared.hideQuickLoading()
                    if !error.isCancelledRequest {
                        GlassAlertManager.shared.showError("下载失败", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func loadFolders() async {
        do {
            let configState = try await apiService.config.getConfigState()
            sourceFolder = configState.sourceFolder
            var folders = try await apiService.folder.getSubfolders(in: sourceFolder)
                .filter { !$0.hidden }
            // 在开头插入源文件夹，方便将文件送回源目录
            let sourceName = URL(fileURLWithPath: sourceFolder).lastPathComponent
            let sourceEntry = FolderInfo(name: sourceName, hidden: false, fileCount: 0)
            folders.insert(sourceEntry, at: 0)
            targetFolders = folders
        } catch {
            GlassAlertManager.shared.showError("加载文件夹失败", message: error.localizedDescription)
        }
    }

    private func performRename() async {
        guard let file = currentFile, !renameText.isEmpty else { return }
        let newName = renameText + file.extension

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
        guard let file = currentFile else { return }
        isOperating = true
        do {
            // 判断是否移动到源文件夹本身
            let sourceName = URL(fileURLWithPath: sourceFolder).lastPathComponent
            let targetPath = folder.name == sourceName ? sourceFolder : sourceFolder + "/" + folder.name
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
    @State private var lastOffset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero
    @State private var gifLoaded = false

    var body: some View {
        let contentURL = apiService.preview.getContentURL(
            for: file.path,
            baseURL: apiService.baseURL,
            apiKey: apiService.apiKey
        )

        GeometryReader { geometry in
            if file.isGif {
                // GIF: 使用 UIKit 的 UIImageView 播放动画
                gifPreview(url: contentURL, in: geometry)
            } else {
                // 普通图片: 使用 AsyncImage
                staticImagePreview(url: contentURL, in: geometry)
            }
        }
    }

    // MARK: - GIF 预览

    @ViewBuilder
    private func gifPreview(url: URL?, in geometry: GeometryProxy) -> some View {
        ZStack {
            // 加载占位
            if !gifLoaded {
                CachedThumbnailView(
                    url: apiService.preview.getThumbnailURL(
                        for: file.path,
                        size: 300,
                        baseURL: apiService.baseURL,
                        apiKey: apiService.apiKey
                    )
                ) { thumb in
                    thumb
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .blur(radius: 8)
                } placeholder: {
                    Color.clear
                }

                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }

            // 动画 GIF
            AnimatedGIFView(url: url) {
                gifLoaded = true
            }
            .opacity(gifLoaded ? 1 : 0)
        }
        .scaleEffect(scale)
        .offset(currentOffset)
        .gesture(pinchGesture)
        .simultaneousGesture(scale > 1.0 ? dragGesture : nil)
        .onTapGesture(count: 2) { resetZoom() }
        .onTapGesture(count: 1, perform: onTap)
        .frame(width: geometry.size.width, height: geometry.size.height)
    }

    // MARK: - 静态图片预览

    @ViewBuilder
    private func staticImagePreview(url: URL?, in geometry: GeometryProxy) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ZStack {
                    CachedThumbnailView(
                        url: apiService.preview.getThumbnailURL(
                            for: file.path,
                            size: 300,
                            baseURL: apiService.baseURL,
                            apiKey: apiService.apiKey
                        )
                    ) { thumb in
                        thumb
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .blur(radius: 8)
                    } placeholder: {
                        Color.clear
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
                    .offset(currentOffset)
                    .gesture(pinchGesture)
                    .simultaneousGesture(scale > 1.0 ? dragGesture : nil)
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

    // MARK: - 缩放手势

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastScale * value.magnification
                scale = min(max(newScale, 0.5), 4.0)
            }
            .onEnded { _ in
                lastScale = scale
                if scale < 1.0 {
                    withAnimation(AppTheme.Animation.spring) {
                        scale = 1.0
                        lastScale = 1.0
                        lastOffset = .zero
                    }
                }
            }
    }

    // MARK: - 拖动手势（仅放大时）

    /// 实时偏移 = 上次结束位置 + 当前拖拽距离
    private var currentOffset: CGSize {
        CGSize(
            width: lastOffset.width + dragTranslation.width,
            height: lastOffset.height + dragTranslation.height
        )
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                lastOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
    }

    private func resetZoom() {
        withAnimation(AppTheme.Animation.spring) {
            scale = scale > 1.0 ? 1.0 : 2.0
            lastScale = scale
            lastOffset = .zero
        }
    }
}

// MARK: - AnimatedGIFView

/// 使用 UIKit UIImageView 播放 GIF 动画
struct AnimatedGIFView: UIViewRepresentable {

    let url: URL?
    var onLoaded: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        let coordinator = context.coordinator

        // URL 未变化则不重复加载
        guard url != coordinator.loadedURL else { return }
        coordinator.loadedURL = url

        guard let url = url else {
            imageView.image = nil
            return
        }

        // 取消上一次加载
        coordinator.loadTask?.cancel()

        // 将引用存入 Coordinator（@unchecked Sendable），避免 Task.detached 捕获非 Sendable 值
        coordinator.imageView = imageView
        coordinator.onLoaded = onLoaded

        coordinator.loadTask = Task.detached { [coordinator] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else { return }
                let animatedImage = Self.decodeGIF(from: data)
                await MainActor.run {
                    coordinator.imageView?.image = animatedImage
                    coordinator.onLoaded?()
                }
            } catch {
                // 加载失败，静默处理
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: @unchecked Sendable {
        var loadedURL: URL?
        var loadTask: Task<Void, Never>?
        weak var imageView: UIImageView?
        var onLoaded: (() -> Void)?
    }

    // MARK: - GIF 解码

    /// 通过 ImageIO 解码 GIF 全部帧，生成可动画的 UIImage
    nonisolated static func decodeGIF(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let frameCount = CGImageSourceGetCount(source)

        // 非动画图片直接返回
        if frameCount <= 1 {
            return UIImage(data: data)
        }

        var frames: [UIImage] = []
        var totalDuration: TimeInterval = 0

        for i in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let duration = Self.frameDuration(from: source, at: i)
            totalDuration += duration
            frames.append(UIImage(cgImage: cgImage))
        }

        guard !frames.isEmpty else { return UIImage(data: data) }

        return UIImage.animatedImage(with: frames, duration: totalDuration)
    }

    /// 读取单帧持续时间
    nonisolated private static func frameDuration(from source: CGImageSource, at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }

        // 优先使用 unclamped delay
        if let delay = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval, delay > 0 {
            return delay
        }
        if let delay = gifDict[kCGImagePropertyGIFDelayTime] as? TimeInterval, delay > 0 {
            return delay
        }

        return 0.1
    }
}

// MARK: - VideoPreviewContent

/// 视频播放预览
struct VideoPreviewContent: View {

    let file: FileInfo
    let apiService: APIService
    @Binding var isPlaying: Bool
    @Binding var showControls: Bool
    let playbackMode: PlaybackMode
    let onVideoEnd: () -> Void

    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1
    @State private var timeObserver: Any?

    // 缩放与拖动
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero

    private var currentOffset: CGSize {
        CGSize(
            width: lastOffset.width + dragTranslation.width,
            height: lastOffset.height + dragTranslation.height
        )
    }

    var body: some View {
        ZStack {
            // 纯视频画面（无内置控制栏）
            if let player = player {
                AVPlayerView(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
        }
        .scaleEffect(scale)
        .offset(currentOffset)
        .gesture(pinchGesture)
        .simultaneousGesture(scale > 1.0 ? dragGesture : nil)
        .onTapGesture(count: 2) { resetZoom() }
        .onTapGesture(count: 1) {
            withAnimation(AppTheme.Animation.standard) {
                showControls.toggle()
            }
        }
        .overlay {

            // 进度条控制层（跟随控制栏显隐）
            if showControls {
                VStack {
                    Spacer()

                    // 进度条 + 时间
                    VStack(spacing: AppTheme.Spacing.sm) {
                        Slider(value: $currentTime, in: 0...max(duration, 0.1)) { editing in
                            if !editing {
                                player?.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                            }
                        }
                        .tint(.white)

                        HStack {
                            Text(formatTime(currentTime))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Text(formatTime(duration))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.bottom, 100) // 给底部统一控制栏留空间
                }
                .transition(.opacity)
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { cleanupPlayer() }
        .onChange(of: isPlaying) { _, newValue in
            guard let player = player else { return }
            if newValue {
                player.play()
            } else {
                player.pause()
            }
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
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak avPlayer] time in
            Task { @MainActor in
                currentTime = time.seconds
                if let item = avPlayer?.currentItem {
                    let dur = item.duration.seconds
                    if dur.isFinite && dur > 0 {
                        duration = dur
                    }
                }
            }
        }

        // 监听播放结束
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            Task { @MainActor in
                switch playbackMode {
                case .repeatCurrent:
                    avPlayer.seek(to: .zero)
                    avPlayer.play()
                case .sequential, .shuffle:
                    isPlaying = false
                    avPlayer.seek(to: .zero)
                    onVideoEnd()
                }
            }
        }

        avPlayer.play()
        isPlaying = true
    }

    private func cleanupPlayer() {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
        timeObserver = nil
        // 注意：不在这里设 isPlaying = false
        // 因为新旧 VideoPreviewContent 共享同一个 @Binding，
        // onDisappear 可能晚于新视图的 onAppear，会覆盖新视频的播放状态
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - 缩放与拖动手势

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastScale * value.magnification
                scale = min(max(newScale, 0.5), 4.0)
            }
            .onEnded { _ in
                lastScale = scale
                if scale < 1.0 {
                    withAnimation(AppTheme.Animation.spring) {
                        scale = 1.0
                        lastScale = 1.0
                        lastOffset = .zero
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                lastOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
    }

    private func resetZoom() {
        withAnimation(AppTheme.Animation.spring) {
            scale = scale > 1.0 ? 1.0 : 2.0
            lastScale = scale
            lastOffset = .zero
        }
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
                .glassBackground(in: Capsule())

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

// MARK: - AVPlayerView

/// 纯视频画面（无内置控制栏）
struct AVPlayerView: UIViewRepresentable {

    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    /// 内部 UIView，承载 AVPlayerLayer
    private class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
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
