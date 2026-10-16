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
import MediaPlayer
import PDFKit

// MARK: - AdvanceMode (chrome tap)

/// 点按模式键：当前结束后是否前进
enum AdvanceMode: String, Codable {
    /// 自动播放下一个
    case autoNext
    /// 单曲循环
    case repeatCurrent

    var iconName: String {
        switch self {
        case .repeatCurrent: return "repeat.1"
        case .autoNext:      return "repeat"
        }
    }

    var label: String {
        switch self {
        case .repeatCurrent: return "单曲循环"
        case .autoNext:      return "自动下一个"
        }
    }

    var toggled: AdvanceMode {
        switch self {
        case .repeatCurrent: return .autoNext
        case .autoNext:      return .repeatCurrent
        }
    }
}

/// Legacy three-way mode kept only so Video/Audio content can compile against
/// a reduced surface: they only need to know whether to loop the current item.
typealias PlaybackMode = AdvanceMode

// MARK: - FilePreviewView

/// 全屏文件预览视图
struct FilePreviewView: View {

    // MARK: - Properties

    let apiService: APIService

    @Environment(\.dismiss) private var dismiss

    // 播放队列
    @State private var playlist: [FileInfo] = []
    @State private var playlistIndex: Int = 0
    let initialUuid: String
    let folderPath: String

    // 控制栏
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    // 文件信息面板
    @State private var showInfoSheet = false
    @State private var fileInfoDetent: FileInfoPanelDetent = .half
    @State private var fileInfoTags: [Tag] = []
    @State private var fileMetadata: FileMetadata? = nil
    @State private var isLoadingFileMetadata = false
    @State private var showTagEditor = false

    // 重命名（pin target — playlistIndex can change while the overlay is open）
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var renameTarget: FileInfo?

    // 移动（pin target — same playlist race as rename）
    @State private var showMoveSheet = false
    @State private var moveTarget: FileInfo?

    // 长按快捷编辑
    @State private var showQuickActions = false
    @State private var allTagsForPicker: [Tag] = []
    @State private var quickSelectedTagIds: Set<Int> = []

    // 视频播放状态
    @State private var isVideoPlaying = false
    @State private var isVideoMuted = false
    @State private var videoCurrentTime: Double = 0
    // 系统音量环
    @State private var systemVolume: Float = AVAudioSession.sharedInstance().outputVolume
    @State private var isVolumeRingActive = false
    @State private var volumeAtDragStart: Float = 0.5
    @State private var volumeActivationTask: Task<Void, Never>?

    // 播放模式（点按）+ 队列面板开关（长按）— 本地持久化
    @State private var advanceMode: AdvanceMode = LocalStorageService.shared.getAdvanceMode()
    @State private var shuffleEnabled: Bool = LocalStorageService.shared.getShuffleEnabled()
    @State private var listLoopEnabled: Bool = LocalStorageService.shared.getListLoopEnabled()
    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var showPlaylistSheet = false
    @State private var playlistAtStart = false
    @State private var playlistAtEnd = false
    /// 下次 shuffle 请求省略 current_queue，强制真打乱
    @State private var shuffleNeedsFresh = true

    // 偏好设置（从本地读取）；同类型过滤也在队列面板调整
    @State private var prefs = LocalStorageService.shared.getPreviewPreferences()

    // 操作状态
    @State private var isOperating = false

    // 调试日志
    @StateObject private var logger = PreviewLogger()
    @State private var showDebugLog = false

    // MARK: - Init

    init(apiService: APIService, uuid: String, folderPath: String) {
        self.apiService = apiService
        self.initialUuid = uuid
        self.folderPath = folderPath
    }

    // MARK: - Computed

    private var currentFile: FileInfo? {
        guard !playlist.isEmpty, playlistIndex >= 0, playlistIndex < playlist.count else { return nil }
        return playlist[playlistIndex]
    }

    /// 当前是否位于回收站中（回收站内禁止再次删除，仅允许移出/还原）
    private var isInRecycleBin: Bool {
        let recycleBinName = IndexedFolder.recycleBinName
        if (folderPath as NSString).lastPathComponent == recycleBinName { return true }
        if let file = currentFile {
            let parent = (file.path as NSString).deletingLastPathComponent
            return (parent as NSString).lastPathComponent == recycleBinName
        }
        return false
    }

    // MARK: - Body
    // Split into sub-trees so Release + SWIFT_STRICT_CONCURRENCY can type-check.

    var body: some View {
        previewWithSheets
            .environmentObject(logger)
    }

    @ViewBuilder
    private var previewStack: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if playlist.isEmpty {
                VStack(spacing: AppTheme.Spacing.lg) {
                    ProgressView()
                        .tint(.white)
                    Text("加载中...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                VStack {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.xs)
                    Spacer()
                }
            } else if let file = currentFile {
                fileContentView(for: file)
                    .id(file.id)
                    .ignoresSafeArea()
                    .longPressToDismiss { dismiss() }

                if showControls {
                    VStack {
                        topControls
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.top, AppTheme.Spacing.xs)
                        Spacer()
                        bottomControls
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private var previewWithLifecycle: some View {
        previewStack
            .ignoresSafeArea(edges: .bottom)
            .navigationBarBackButtonHidden(true)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .statusBarHidden(!showControls)
            .animation(AppTheme.Animation.standard, value: showControls)
            .onChange(of: playlistIndex) { _, _ in
                handlePlaylistIndexChanged()
            }
            .onChange(of: playlist.count) { _, _ in
                publishE2EPlaylistMeta()
            }
            .onChange(of: shuffleEnabled) { _, _ in
                refreshNowPlayingSkipAvailability()
            }
            .onChange(of: listLoopEnabled) { _, _ in
                refreshNowPlayingSkipAvailability()
            }
            .onChange(of: playlistAtStart) { _, _ in
                refreshNowPlayingSkipAvailability()
            }
            .onChange(of: playlistAtEnd) { _, _ in
                refreshNowPlayingSkipAvailability()
            }
            .onChange(of: showInfoSheet) { _, isOpen in
                if isOpen {
                    cancelAutoAdvanceTimer()
                } else {
                    startAutoAdvanceTimer()
                }
            }
            .onAppear {
                NavigationState.shared.hideTabBar = true
                scheduleAutoHide()
                refreshNowPlayingSkipAvailability()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nowPlayingRemotePlay)) { _ in
                isVideoPlaying = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .nowPlayingRemotePause)) { _ in
                isVideoPlaying = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .nowPlayingRemoteToggle)) { _ in
                isVideoPlaying.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nowPlayingRemoteNext)) { _ in
                guard canGoNext else { return }
                navigateInPlaylist(direction: 1, skipNonPlayable: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nowPlayingRemotePrevious)) { _ in
                guard canGoPrev else { return }
                navigateInPlaylist(direction: -1, skipNonPlayable: true)
            }
            .task {
                if ProcessInfo.processInfo.environment["E2E_NOWPLAYING_PROBE"] == "1" {
                    listLoopEnabled = LocalStorageService.shared.getListLoopEnabled()
                    shuffleEnabled = LocalStorageService.shared.getShuffleEnabled()
                    prefs = LocalStorageService.shared.getPreviewPreferences()
                    advanceMode = LocalStorageService.shared.getAdvanceMode()
                }
                if shuffleEnabled { shuffleNeedsFresh = true }
                await fetchPlaylist(uuid: initialUuid, keepShuffleQueue: false)
                refreshNowPlayingSkipAvailability()
            }
            .onDisappear {
                hideControlsTask?.cancel()
                cancelAutoAdvanceTimer()
                NowPlayingController.shared.clear()
                NavigationState.shared.hideTabBar = false
            }
    }

    private var previewWithSheets: some View {
        previewWithLifecycle
            .fileInfoPanel(
                isPresented: $showInfoSheet,
                selectedDetent: $fileInfoDetent,
                title: "文件信息",
                actions: { fileInfoActions },
                modules: { fileInfoModules }
            )
            .overlay {
                if showRenameAlert {
                    renameAlertOverlay
                }
            }
            .animation(AppTheme.Animation.spring, value: showRenameAlert)
            .sheet(isPresented: $showMoveSheet) {
                MoveSheetView(
                    apiService: apiService,
                    sourceFolder: NavigationState.shared.sourceFolder,
                    file: moveTarget ?? currentFile,
                    uuids: (moveTarget ?? currentFile)?.uuid.map { [$0] } ?? [],
                    onDismiss: {
                        showMoveSheet = false
                        moveTarget = nil
                    },
                    onMoved: { folderName, _ in
                        showMoveSheet = false
                        moveTarget = nil
                        GlassAlertManager.shared.showSuccess("已移动到 \(folderName)")
                        handlePostOperation()
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showTagEditor) {
                if let file = currentFile, let uuid = file.uuid {
                    TagEditorView(
                        apiService: apiService,
                        sourceFolder: NavigationState.shared.sourceFolder,
                        fileUuid: uuid,
                        onDismiss: { updatedTags in
                            fileInfoTags = updatedTags
                        }
                    )
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $showDebugLog) {
                DebugLogSheet(logger: logger, fileName: currentFile?.name ?? "")
                    .presentationDetents([.medium, .large])
            }
            .overlay {
                if showQuickActions {
                    quickEditPopup
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .animation(AppTheme.Animation.spring, value: showQuickActions)
    }

    @ViewBuilder
    private var renameAlertOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showRenameAlert = false }

            VStack(spacing: AppTheme.Spacing.lg) {
                HStack {
                    TextField("文件名", text: $renameText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("renameTextField")
                    Text((renameTarget ?? currentFile).map { $0.extension.isEmpty ? "" : ".\($0.extension)" } ?? "")
                        .foregroundStyle(.tertiary)
                }
                .padding(AppTheme.Spacing.md)
                .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))

                HStack(spacing: AppTheme.Spacing.md) {
                    GlassButton(icon: "trash", style: .secondary, size: .medium) {
                        renameText = ""
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("清空")

                    GlassButton(icon: "checkmark", style: .primary, size: .medium) {
                        showRenameAlert = false
                        Task { await performRename() }
                    }
                    .disabled(renameText.isEmpty || renameText == (renameTarget ?? currentFile)?.baseName)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("renameConfirmButton")
                    .accessibilityLabel("确认")

                    GlassButton(icon: "xmark", style: .secondary, size: .medium) {
                        showRenameAlert = false
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("取消")
                }
            }
            .padding(AppTheme.Spacing.xxl)
            .frame(maxWidth: 340)
            .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    // MARK: - 文件内容路由

    @ViewBuilder
    private func fileContentView(for file: FileInfo) -> some View {
        switch file.fileType {
        case .image, .gif:
            ImagePreviewContent(
                file: file,
                apiService: apiService,
                onTap: { toggleControls() },
                onSwipe: { direction in handleImageSwipe(direction: direction) }
            )
        case .video:
            VideoPreviewContent(
                file: file,
                apiService: apiService,
                isPlaying: $isVideoPlaying,
                isMuted: $isVideoMuted,
                currentTime: $videoCurrentTime,
                showControls: $showControls,
                playbackMode: advanceMode,
                onVideoEnd: { advanceToNext() },
                onTap: { toggleControls() }
            )
        case .audio:
            AudioPreviewContent(
                file: file,
                apiService: apiService,
                isPlaying: $isVideoPlaying,
                isMuted: $isVideoMuted,
                currentTime: $videoCurrentTime,
                showControls: $showControls,
                playbackMode: advanceMode,
                onAudioEnd: { advanceToNext() },
                onTap: { toggleControls() }
            )
        case .pdf:
            PDFPreviewContent(
                file: file,
                apiService: apiService,
                onTap: { toggleControls() }
            )
        case .other:
            OtherFilePreviewContent(
                file: file,
                onTap: { toggleControls() }
            )
        }
    }

    // MARK: - 顶部标题栏

    private var topControls: some View {
        HStack(spacing: AppTheme.Spacing.sm) {

            // 返回按钮
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.85), in: Circle())
                .onTapGesture { dismiss() }

            // 文件名胶囊（点击查看详情，长按看日志，支持横向滚动）
            ScrollView(.horizontal, showsIndicators: false) {
                Text(currentFile?.name ?? "")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, AppTheme.Spacing.md)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(.white.opacity(0.85), in: Capsule())
            .contentShape(Capsule())
            .accessibilityIdentifier("previewFileNameCapsule")
            .accessibilityLabel("文件信息")
            .accessibilityValue(currentFile?.name ?? "")
            .accessibilityAddTraits(.isButton)
            .simultaneousGesture(TapGesture().onEnded {
                openInfoSheetForCurrentFile()
            })
            .onLongPressGesture {
                if let file = currentFile {
                    renameText = file.baseName
                }
                quickSelectedTagIds = Set(fileInfoTags.map { $0.id })
                allTagsForPicker = []
                showQuickActions = true
                Task {
                    allTagsForPicker = (try? await apiService.tag.getTags(
                        sourceFolder: NavigationState.shared.sourceFolder
                    )) ?? []
                }
            }

            // 模式键：点按 = 单曲↔自动下一个；长按 = 队列面板
            Image(systemName: advanceMode.iconName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(advanceMode == .repeatCurrent ? .black : .white)
                .frame(width: 48, height: 48)
                .background(
                    advanceMode == .repeatCurrent
                        ? Color.white.opacity(0.85)
                        : Color.blue.opacity(0.85),
                    in: Circle()
                )
                .accessibilityIdentifier("playbackModeButton")
                .accessibilityLabel(advanceMode.label)
                .accessibilityHint("长按打开队列面板")
                .onTapGesture {
                    withAnimation(AppTheme.Animation.standard) {
                        advanceMode = advanceMode.toggled
                    }
                    LocalStorageService.shared.saveAdvanceMode(advanceMode)
                    cancelAutoAdvanceTimer()
                    startAutoAdvanceTimer()
                }
                .onLongPressGesture {
                    showPlaylistSheet = true
                }
                .popover(isPresented: $showPlaylistSheet) {
                    playlistPopoverContent
                }
        }
    }

    // MARK: - 底部导航按钮

    /// E2E 下以 LocalStorage 为准（避免 @State 与冷启动注入短暂不一致）
    private var effectiveShuffleEnabled: Bool {
        if ProcessInfo.processInfo.environment["E2E_NOWPLAYING_PROBE"] == "1" {
            return LocalStorageService.shared.getShuffleEnabled()
        }
        return shuffleEnabled
    }

    private var effectiveListLoopEnabled: Bool {
        if ProcessInfo.processInfo.environment["E2E_NOWPLAYING_PROBE"] == "1" {
            return LocalStorageService.shared.getListLoopEnabled()
        }
        return listLoopEnabled
    }

    private var canGoPrev: Bool {
        guard playlist.count > 1 else { return false }
        if effectiveShuffleEnabled || effectiveListLoopEnabled { return true }
        return !(playlistAtStart && playlistIndex <= 0)
    }

    private var canGoNext: Bool {
        guard playlist.count > 1 else { return false }
        if effectiveShuffleEnabled || effectiveListLoopEnabled { return true }
        return !(playlistAtEnd && playlistIndex >= playlist.count - 1)
    }

    private var bottomControls: some View {
        HStack {
            // 上一个（锁屏远程 previous 复用同一 navigateInPlaylist）
            Button {
                navigateInPlaylist(direction: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.85))
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("previewPrevButton")
            .opacity(canGoPrev ? 1.0 : 0.3)
            .disabled(!canGoPrev)

            Spacer()

            // 视频/音频控制按钮组
            if currentFile?.isVideo == true || currentFile?.isAudio == true {
                HStack(spacing: AppTheme.Spacing.md) {
                    // 静音/解除静音 + 长按拖拽调系统音量
                    ZStack {
                        // 音量环（长按后出现）
                        if isVolumeRingActive {
                            ZStack {
                                // 背景圆弧
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 3.5)
                                    .frame(width: 64, height: 64)
                                // 音量进度弧（顺时针从12点开始）
                                Circle()
                                    .trim(from: 0, to: CGFloat(systemVolume))
                                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                                    .frame(width: 64, height: 64)
                                    .rotationEffect(.degrees(-90))
                            }
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                        }

                        // 静音按钮本体
                        Image(systemName: isVideoMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(isVolumeRingActive ? 1.0 : 0.85))
                            .clipShape(Circle())
                            // 长按 → 显示音量环；长按不抬起拖动 → 左增右减系统音量；短按 → 切换静音
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                    .onChanged { drag in
                                        // 首次触碰：记录起始音量，启动 0.4s 延时激活音量环
                                        if volumeActivationTask == nil && !isVolumeRingActive {
                                            volumeAtDragStart = systemVolume
                                            volumeActivationTask = Task { @MainActor in
                                                try? await Task.sleep(for: .milliseconds(400))
                                                guard !Task.isCancelled else { return }
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    isVolumeRingActive = true
                                                }
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            }
                                        }
                                        // 音量环已激活：拖拽调整音量
                                        if isVolumeRingActive {
                                            let deltaX = Float(drag.translation.width)
                                            let sensitivity: Float = 160
                                            let newVol = max(0, min(1, volumeAtDragStart + (-deltaX / sensitivity)))
                                            systemVolume = newVol
                                        }
                                    }
                                    .onEnded { _ in
                                        volumeActivationTask?.cancel()
                                        volumeActivationTask = nil
                                        // 未激活音量环 = 短按 → 切换静音
                                        if !isVolumeRingActive {
                                            isVideoMuted.toggle()
                                        }
                                        // 松手收起音量环
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            isVolumeRingActive = false
                                        }
                                    }
                            )
                    }
                    // 隐藏的 MPVolumeView，用于读写系统音量
                    .background(
                        SystemVolumeControlView(volume: $systemVolume)
                            .frame(width: 1, height: 1)
                            .opacity(0.001)
                    )

                    // 播放/暂停（锁屏远程 play/pause 写同一 isVideoPlaying）
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
                    .accessibilityIdentifier("previewPlayPauseButton")

                    // 截图（仅视频）
                    if currentFile?.isVideo == true {
                        Button {
                            captureVideoScreenshot()
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.85))
                                .clipShape(Circle())
                        }
                    }
                }
            }

            Spacer()

            // 下一个（锁屏远程 next 复用同一 navigateInPlaylist）
            Button {
                navigateInPlaylist(direction: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.85))
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("previewNextButton")
            .opacity(canGoNext ? 1.0 : 0.3)
            .disabled(!canGoNext)
        }
        .padding(.horizontal, AppTheme.Spacing.xxl)
        .padding(.bottom, AppTheme.Spacing.xxl)
    }

    // MARK: - 文件信息面板内容

    private func handlePlaylistIndexChanged() {
        scheduleAutoHide()
        startAutoAdvanceTimer()
        logger.clear()
        refreshNowPlayingSkipAvailability()
        publishE2EPlaylistMeta()
        // 切曲时若信息面板仍开着，必须同步 metadata，否则会出现
        // 顶栏 clip.mp4、面板却仍是上一张 HEIC EXIF 的错配（TF 041 用户截图）。
        if showInfoSheet {
            reloadFileMetadataForCurrentFile()
        }
    }

    private func openInfoSheetForCurrentFile() {
        fileInfoDetent = .half
        showInfoSheet = true
        cancelAutoAdvanceTimer()
        reloadFileMetadataForCurrentFile()
        Task { await resolveUuidAndLoadTags() }
    }

    /// 按当前曲目刷新 metadata；用 path 校验丢弃过期响应，避免顶栏/面板文件名错配。
    private func reloadFileMetadataForCurrentFile() {
        let path = currentFile?.path
        fileInfoTags = []
        fileMetadata = nil
        isLoadingFileMetadata = path != nil
        guard let path else {
            isLoadingFileMetadata = false
            return
        }
        Task {
            let meta = try? await apiService.file.getMetadata(path: path)
            await MainActor.run {
                // 仅当仍停留在同一 path 时采纳（切曲 / 快速连点会作废旧请求）
                guard currentFile?.path == path else { return }
                fileMetadata = meta
                isLoadingFileMetadata = false
            }
        }
    }

    @ViewBuilder
    private var fileInfoModules: some View {
        if let file = currentFile {
            FileInfoSheetContent(
                file: file,
                metadata: fileMetadata,
                isLoadingMetadata: isLoadingFileMetadata,
                position: "\(playlistIndex + 1) / \(playlist.count)",
                showsActions: false,
                tags: fileInfoTags,
                onAddTag: file.uuid != nil ? {
                    showInfoSheet = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        showTagEditor = true
                    }
                } : nil,
                onShowDebugLog: {
                    showInfoSheet = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        showDebugLog = true
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var fileInfoActions: some View {
        if let file = currentFile {
            FileInfoActionsRow(
                onDownload: {
                    showInfoSheet = false
                    saveFileToDevice(file)
                },
                onShare: {
                    showInfoSheet = false
                    shareFile(file)
                },
                onMove: {
                    let target = file
                    moveTarget = target
                    showInfoSheet = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        showMoveSheet = true
                    }
                },
                onRename: {
                    let target = file
                    renameTarget = target
                    showInfoSheet = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        renameText = target.baseName
                        showRenameAlert = true
                    }
                },
                onDelete: (file.uuid != nil && !isInRecycleBin) ? {
                    showInfoSheet = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        promptDelete(file: file)
                    }
                } : nil
            )
        }
    }


    // MARK: - 长按快捷编辑浮窗

    private var quickEditPopup: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showQuickActions = false }

            VStack(spacing: AppTheme.Spacing.lg) {
                // 文件名输入框
                HStack {
                    TextField("", text: $renameText)
                        .textFieldStyle(.plain)
                    Text(currentFile.map { $0.extension.isEmpty ? "" : ".\($0.extension)" } ?? "")
                        .foregroundStyle(.tertiary)
                }
                .padding(AppTheme.Spacing.md)
                .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))

                // 标签选择
                if allTagsForPicker.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.sm)
                } else {
                    ScrollView {
                        FlowLayout(spacing: 8) {
                            ForEach(allTagsForPicker) { tag in
                                let isSelected = quickSelectedTagIds.contains(tag.id)
                                Button {
                                    if isSelected { quickSelectedTagIds.remove(tag.id) }
                                    else { quickSelectedTagIds.insert(tag.id) }
                                } label: {
                                    HStack(spacing: 4) {
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                        Text(tag.name)
                                            .font(.subheadline)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        isSelected
                                            ? Color(hex: tag.color).opacity(0.85)
                                            : Color(hex: tag.color).opacity(0.6)
                                    )
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                }

                // 按钮
                HStack(spacing: AppTheme.Spacing.md) {
                    GlassButton("取消", style: .secondary, size: .medium) {
                        showQuickActions = false
                    }
                    .frame(maxWidth: .infinity)

                    GlassButton("确认", style: .primary, size: .medium) {
                        showQuickActions = false
                        guard let file = currentFile else { return }
                        if !renameText.isEmpty && renameText != file.baseName {
                            Task { await performRename() }
                        }
                        if let uuid = file.uuid {
                            let ids = Array(quickSelectedTagIds)
                            Task {
                                try? await apiService.tag.setFileTags(fileUuid: uuid, tagIds: ids)
                                fileInfoTags = (try? await apiService.tag.getFileTags(fileUuid: uuid)) ?? []
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(AppTheme.Spacing.xxl)
            .frame(maxWidth: 340)
            .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
        }
    }

    // MARK: - UUID 解析 + 标签加载

    /// 解析当前文件的 UUID（如果为空则通过 indexer 查找）
    /// 用于预览页打开时自动调用，确保内容加载使用 UUID-based URL
    /// 加载当前文件的标签
    private func resolveUuidAndLoadTags() async {
        if let uuid = currentFile?.uuid {
            fileInfoTags = (try? await apiService.tag.getFileTags(fileUuid: uuid)) ?? []
        }
    }

    // MARK: - 控制栏显示/隐藏

    /// 是否允许隐藏控制栏（仅视觉内容：图片/GIF/视频/PDF）
    private var canHideControls: Bool {
        guard let file = currentFile else { return false }
        return file.isVideo || file.isImage || file.isGif || file.isPdf
    }

    private func toggleControls() {
        guard prefs.allowToggleUI, canHideControls else { return }
        withAnimation(AppTheme.Animation.standard) {
            showControls.toggle()
        }
        if showControls {
            scheduleAutoHide()
        }
    }

    private func scheduleAutoHide() {
        hideControlsTask?.cancel()
        guard prefs.allowToggleUI else { return }
        guard prefs.autoHideDelay > 0 else { return }
        // 只对视频自动隐藏（图片/PDF/音频/其他 不自动隐藏）
        guard currentFile?.isVideo == true else { return }
        let delay = prefs.autoHideDelay
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(AppTheme.Animation.standard) {
                    showControls = false
                }
            }
        }
    }

    // MARK: - 播放模式逻辑

    // MARK: - Playlist Popover

    private var playlistPopoverContent: some View {
        VStack(spacing: 0) {
            // Independent switches (not a radio group)
            VStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { shuffleEnabled },
                    set: { setShuffleEnabled($0) }
                )) {
                    Text("随机播放")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("queueShuffleToggle")

                Toggle(isOn: Binding(
                    get: { listLoopEnabled },
                    set: { setListLoopEnabled($0) }
                )) {
                    Text("列表循环")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("queueListLoopToggle")

                Toggle(isOn: Binding(
                    get: { prefs.filterAutoplayByFileType },
                    set: { setFilterByType($0) }
                )) {
                    Text("同类型播放")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("queueSameTypeToggle")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(playlist.enumerated()), id: \.element.id) { i, file in
                        Button {
                            jumpToPlaylistFile(file)
                        } label: {
                            HStack(spacing: 8) {
                                Text("\(i + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 14, alignment: .trailing)

                                Text(file.name)
                                    .font(.caption)
                                    .foregroundStyle(i == playlistIndex ? .primary : .secondary)
                                    .fontWeight(i == playlistIndex ? .semibold : .regular)
                                    .lineLimit(1)

                                Spacer()

                                Text(file.extension.uppercased())
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)

                                if i == playlistIndex {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(i == playlistIndex ? Color.blue.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("queueItem-\(file.uuid ?? file.path)")

                        if i < playlist.count - 1 {
                            Divider().padding(.leading, 34)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 280)
        // Keep toggle children discoverable by XCUITest (same pattern as batchActionBar).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("queuePanel")
        .presentationCompactAdaptation(.popover)
    }

    private func setShuffleEnabled(_ on: Bool) {
        shuffleEnabled = on
        LocalStorageService.shared.saveShuffleEnabled(on)
        if on { shuffleNeedsFresh = true }
        if let file = currentFile {
            Task { await fetchPlaylist(uuid: file.uuid ?? file.path, keepShuffleQueue: false) }
        }
    }

    private func setListLoopEnabled(_ on: Bool) {
        listLoopEnabled = on
        LocalStorageService.shared.saveListLoopEnabled(on)
        if let file = currentFile {
            Task { await fetchPlaylist(uuid: file.uuid ?? file.path, keepShuffleQueue: !shuffleNeedsFresh) }
        }
    }

    private func setFilterByType(_ on: Bool) {
        prefs.filterAutoplayByFileType = on
        LocalStorageService.shared.savePreviewPreferences(prefs)
        if shuffleEnabled { shuffleNeedsFresh = true }
        if let file = currentFile {
            Task { await fetchPlaylist(uuid: file.uuid ?? file.path, keepShuffleQueue: false) }
        }
    }

    // MARK: - Playlist Navigation

    private func apiPlaylistMode() -> String {
        if effectiveShuffleEnabled { return "shuffle" }
        if effectiveListLoopEnabled { return "list_loop" }
        return "sequential"
    }

    /// Fetch playlist from server centered on given UUID
    private func fetchPlaylist(uuid: String, keepShuffleQueue: Bool = true) async {
        let mode = apiPlaylistMode()
        let filterByType = prefs.filterAutoplayByFileType
        // 首拉时 playlist 为空 → currentFile 为 nil；若仍要同类型，先无过滤拉一次再按当前项类型重拉
        var fileType = filterByType ? currentFile?.fileType.rawValue : nil

        // True shuffle: omit current_queue on first enter / jump so neighbors aren't sequential
        let sendQueue = mode == "shuffle" && keepShuffleQueue && !shuffleNeedsFresh && !playlist.isEmpty
        let queue: [String]? = sendQueue ? playlist.compactMap(\.uuid) : nil

        do {
            var resp = try await apiService.preview.getPlaylist(
                uuid: uuid, folderPath: folderPath, mode: mode,
                fileType: fileType, currentQueue: queue
            )
            if filterByType, fileType == nil {
                let seed = resp.items.indices.contains(resp.currentIndex)
                    ? resp.items[resp.currentIndex]
                    : resp.items.first
                if let inferred = seed?.fileType, !inferred.isEmpty {
                    fileType = inferred
                    resp = try await apiService.preview.getPlaylist(
                        uuid: uuid, folderPath: folderPath, mode: mode,
                        fileType: fileType, currentQueue: queue
                    )
                }
            }
            let files = resp.items.map { $0.toFileInfo() }
            await MainActor.run {
                withAnimation {
                    playlist = files
                    playlistIndex = resp.currentIndex
                    playlistAtStart = resp.atStart ?? false
                    playlistAtEnd = resp.atEnd ?? false
                }
                if mode == "shuffle" { shuffleNeedsFresh = false }
                startAutoAdvanceTimer()
                publishE2EPlaylistMeta()
            }
        } catch {}
    }

    /// 图片左右滑动切页；仅剩一个文件（无处可去）时返回 false，由手势层给出边界反馈
    private func handleImageSwipe(direction: Int) -> Bool {
        if direction < 0 && !canGoPrev { return false }
        if direction > 0 && !canGoNext { return false }
        guard playlist.count > 1 else { return false }
        navigateInPlaylist(direction: direction)
        return true
    }

    /// Navigate within the playlist (direction: +1 forward, -1 backward)
    /// list_loop 滑动窗会在两端填充重复项；必须跳过与当前相同 uuid，否则遥控 next/prev 会「假换曲」。
    /// `skipNonPlayable`：自动连播 / 锁屏遥控时跳过图片等，避免后台播放停住。
    private func navigateInPlaylist(direction: Int, skipNonPlayable: Bool = false) {
        let wrap = effectiveShuffleEnabled || effectiveListLoopEnabled
        guard let idx = PlaylistAdvance.nextIndex(
            playlist: playlist,
            from: playlistIndex,
            direction: direction,
            wrap: wrap,
            skipNonPlayable: skipNonPlayable
        ) else { return }

        withAnimation { playlistIndex = idx }
        cancelAutoAdvanceTimer()
        startAutoAdvanceTimer()
        refreshNowPlayingSkipAvailability()
        if wrap && (idx == 0 || idx == playlist.count - 1) {
            let file = playlist[idx]
            Task { await fetchPlaylist(uuid: file.uuid ?? file.path, keepShuffleQueue: effectiveShuffleEnabled) }
        }
    }

    /// Jump to a specific file in the playlist
    private func jumpToPlaylistFile(_ file: FileInfo) {
        showPlaylistSheet = false
        if shuffleEnabled { shuffleNeedsFresh = true }
        Task { await fetchPlaylist(uuid: file.uuid ?? file.path, keepShuffleQueue: false) }
    }

    /// Called when media playback ends — 跳过非音视频以保持后台连播
    private func advanceToNext() {
        // 信息面板打开时禁止自动切曲，否则会出现 chrome 已变、面板仍挂旧 EXIF 的错配窗口
        if showInfoSheet { return }
        if advanceMode == .repeatCurrent { return }
        navigateInPlaylist(direction: 1, skipNonPlayable: true)
    }

    /// Auto-advance timer for static content (images, PDF, other)
    private func startAutoAdvanceTimer() {
        cancelAutoAdvanceTimer()
        guard !showInfoSheet else { return }
        guard advanceMode != .repeatCurrent else { return }
        guard currentFile?.isVideo != true && currentFile?.isAudio != true else { return }

        let delay = prefs.imageAutoAdvanceSeconds
        autoAdvanceTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !showInfoSheet else { return }
                advanceToNext()
            }
        }
    }

    private func cancelAutoAdvanceTimer() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
    }

    // MARK: - Now Playing / 远程控制

    private func refreshNowPlayingSkipAvailability() {
        let npc = NowPlayingController.shared
        npc.canGoPrevious = canGoPrev
        npc.canGoNext = canGoNext
        publishE2EPlaylistMeta()
    }

    private func publishE2EPlaylistMeta() {
        guard ProcessInfo.processInfo.environment["E2E_NOWPLAYING_PROBE"] == "1" else { return }
        E2EHarness.shared.playlistMeta = "\(playlist.count)|\(playlistIndex)|\(canGoNext ? 1 : 0)|\(canGoPrev ? 1 : 0)"
    }

    // MARK: - 视频截图

    private func captureVideoScreenshot() {
        guard let file = currentFile else { return }
        let url: URL? = if let uuid = file.uuid {
            apiService.preview.getContentURL(
                uuid: uuid,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        } else {
            apiService.preview.getContentURL(
                for: file.path,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        }
        guard let url else {
            GlassAlertManager.shared.showError("无法获取文件地址")
            return
        }

        GlassAlertManager.shared.showQuickLoading()

        // 在进入 Task.detached 前捕获所需值，避免 Swift 6 Sendable 问题
        let captureTime = videoCurrentTime
        let screenshotName = "\(file.baseName)_\(Int(captureTime))s.jpg"

        Task.detached {
            do {
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero

                let time = CMTime(seconds: captureTime, preferredTimescale: 600)
                let (cgImage, _) = try await generator.image(at: time)
                let uiImage = UIImage(cgImage: cgImage)

                guard let imageData = uiImage.jpegData(compressionQuality: 0.95) else {
                    await MainActor.run {
                        GlassAlertManager.shared.hideQuickLoading()
                        GlassAlertManager.shared.showError("截图失败")
                    }
                    return
                }

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
                    PhotoExporter.saveFile(toPhotos: imageData, fileName: screenshotName) { success, error in
                        if success {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: error ?? APIError.unknown("保存失败"))
                        }
                    }
                }

                await MainActor.run {
                    GlassAlertManager.shared.hideQuickLoading()
                    GlassAlertManager.shared.showSuccess("截图已保存到相册")
                }
            } catch {
                await MainActor.run {
                    GlassAlertManager.shared.hideQuickLoading()
                    if !error.isCancelledRequest {
                        GlassAlertManager.shared.showError("截图失败", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: - 文件操作

    /// 拉取文件到临时目录并弹出系统分享面板（Info 面板「分享」）
    private func shareFile(_ file: FileInfo) {
        let contentURL: URL? = if let uuid = file.uuid {
            apiService.preview.getContentURL(
                uuid: uuid,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        } else {
            apiService.preview.getContentURL(
                for: file.path,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        }
        guard let contentURL else {
            GlassAlertManager.shared.showError("无法获取文件地址")
            return
        }

        GlassAlertManager.shared.showQuickLoading()
        Task.detached {
            do {
                let (data, _) = try await URLSession.shared.data(from: contentURL)
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(file.name)
                try data.write(to: tempURL)
                await MainActor.run {
                    GlassAlertManager.shared.hideQuickLoading()
                    presentShareSheet(items: [tempURL])
                }
            } catch {
                await MainActor.run {
                    GlassAlertManager.shared.hideQuickLoading()
                    if !error.isCancelledRequest {
                        GlassAlertManager.shared.showError("分享失败", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func presentShareSheet(items: [Any]) {
        let activityVC = UIActivityViewController(
            activityItems: items,
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

    private func saveFileToDevice(_ file: FileInfo) {
        let contentURL: URL? = if let uuid = file.uuid {
            apiService.preview.getContentURL(
                uuid: uuid,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        } else {
            apiService.preview.getContentURL(
                for: file.path,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        }
        guard let contentURL else {
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


    private func performRename() async {
        guard let file = renameTarget ?? currentFile, let uuid = file.uuid, !renameText.isEmpty else { return }
        let newName = file.extension.isEmpty ? renameText : renameText + "." + file.extension

        isOperating = true
        do {
            _ = try await apiService.file.renameFile(uuid: uuid, to: newName)
            // 重命名成功后只更新目标项（可能不是 current playlistIndex）
            let ext = file.extension
            let updated = FileInfo(
                uuid: file.uuid,
                name: newName,
                path: (file.path as NSString).deletingLastPathComponent + "/" + newName,
                fileType: file.fileType,
                extension: ext,
                size: file.size,
                created: file.created,
                modified: file.modified,
                width: file.width,
                height: file.height,
                duration: file.duration,
                sourceUrl: file.sourceUrl
            )
            if let idx = playlist.firstIndex(where: { $0.uuid == uuid }) {
                playlist[idx] = updated
            } else if playlist.indices.contains(playlistIndex) {
                playlist[playlistIndex] = updated
            }
            renameTarget = nil
            GlassAlertManager.shared.showSuccess("重命名成功")
        } catch {
            GlassAlertManager.shared.showError("重命名失败", message: error.localizedDescription)
        }
        isOperating = false
    }


    /// 弹出删除确认（软删除到回收站）
    private func promptDelete(file: FileInfo) {
        GlassConfirmManager.shared.show(
            config: GlassConfirmConfig(
                title: "删除此文件？",
                message: "文件将被移动到回收站，可稍后在回收站中还原。",
                icon: "trash.fill",
                iconColor: .red,
                confirmTitle: "删除",
                confirmStyle: .destructive,
                cancelTitle: "取消"
            ),
            onConfirm: {
                Task { @MainActor in await performDelete(file: file) }
            }
        )
    }

    /// 执行软删除：调用服务器接口将文件移入回收站
    private func performDelete(file: FileInfo) async {
        guard let uuid = file.uuid else { return }
        isOperating = true
        do {
            _ = try await apiService.file.deleteFile(uuid: uuid)
            GlassAlertManager.shared.showSuccess("已移到回收站")
            handlePostOperation()
        } catch {
            GlassAlertManager.shared.showError("删除失败", message: error.localizedDescription)
        }
        isOperating = false
    }

    /// 操作完成后的导航逻辑
    private func handlePostOperation() {
        playlist.remove(at: playlistIndex)
        if playlist.isEmpty {
            dismiss()
        } else if playlistIndex >= playlist.count {
            playlistIndex = playlist.count - 1
        }
    }
}

// MARK: - ImagePreviewContent

/// 图片/GIF 预览（支持双指缩放）
struct ImagePreviewContent: View {

    let file: FileInfo
    let apiService: APIService
    let onTap: () -> Void
    /// scale == 1.0 时左右滑动切页；direction: -1 上一张 / +1 下一张，返回 false 表示已到头
    let onSwipe: (Int) -> Bool

    @State private var scale: CGFloat = 1.0
    @State private var gifLoaded = false

    var body: some View {
        let contentURL: URL? = if let uuid = file.uuid {
            apiService.preview.getContentURL(
                uuid: uuid,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        } else {
            apiService.preview.getContentURL(
                for: file.path,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        }

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
                    url: file.thumbnailURL(apiService: apiService)
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
        .frame(width: geometry.size.width, height: geometry.size.height)
        .contentShape(Rectangle())
        .zoomPanGesture(scale: $scale)
        .pageSwipeGesture(isEnabled: scale <= 1.0, onSwipe: onSwipe)
        .onTapGesture(count: 1, perform: onTap)
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

            case .failure:
                VStack(spacing: AppTheme.Spacing.lg) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("图片加载失败")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }

            @unknown default:
                EmptyView()
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .contentShape(Rectangle())
        .zoomPanGesture(scale: $scale)
        .pageSwipeGesture(isEnabled: scale <= 1.0, onSwipe: onSwipe)
        .onTapGesture(count: 1, perform: onTap)
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

    @EnvironmentObject private var logger: PreviewLogger

    let file: FileInfo
    let apiService: APIService
    @Binding var isPlaying: Bool
    @Binding var isMuted: Bool
    @Binding var currentTime: Double
    @Binding var showControls: Bool
    let playbackMode: PlaybackMode
    let onVideoEnd: () -> Void
    let onTap: () -> Void

    @State private var player: AVPlayer?
    /// 勿默认 1：未就绪时写入 Now Playing 会让锁屏进度条显示约 1 秒总时长
    @State private var duration: Double = 0
    @State private var timeObserver: Any?
    @State private var isBuffering = true  // 缓冲/转码加载中
    @State private var statusObserver: NSKeyValueObservation?

    // 缩放
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // 纯视频画面（无内置控制栏）
            if let player = player {
                AVPlayerView(player: player)
                    .ignoresSafeArea()
            }

            // 加载指示器：player 未创建或缓冲中时显示
            if player == nil || isBuffering {
                ZStack {
                    Color.black
                    VStack(spacing: AppTheme.Spacing.md) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                        Text("加载中...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .zoomPanGesture(scale: $scale)
        .seekDragGesture(isEnabled: scale <= 1.0, currentTime: currentTime, duration: duration) { target in
            currentTime = target
            player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        }
        .onTapGesture(count: 1) { onTap() }
        .overlay {

            // 进度条控制层（跟随控制栏显隐）
            if showControls && !isBuffering {
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
            NowPlayingController.shared.updatePlaybackProgress(
                elapsed: currentTime,
                duration: duration,
                isPlaying: newValue
            )
        }
        .onChange(of: isMuted) { _, newValue in
            player?.isMuted = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .nowPlayingRemoteSeek)) { note in
            guard let position = note.userInfo?[NowPlayingController.seekPositionKey] as? TimeInterval else { return }
            seekTo(position)
        }
    }

    // MARK: - 播放器管理

    private func setupPlayer() {
        let url: URL? = if let uuid = file.uuid {
            apiService.preview.getContentURL(
                uuid: uuid,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        } else {
            apiService.preview.getContentURL(
                for: file.path,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        }
        guard let url else { return }

        // 后台继续出声（画面可停，音频轨继续）
        NowPlayingController.shared.activatePlaybackSession()

        isBuffering = true
        // 索引元数据优先于占位 1s；流媒体 item.duration 未就绪时也能先写出真实总时长
        duration = MediaDurationResolver.resolve(
            playerItem: nil,
            fileDuration: file.duration,
            current: 0
        )
        logger.info("视频 URL: \(url.absoluteString)")

        let avPlayer = AVPlayer(url: url)
        avPlayer.isMuted = isMuted
        player = avPlayer

        NowPlayingController.shared.onSeek = { [weak avPlayer] position in
            avPlayer?.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }

        // KVO 监听 currentItem.status，等待 readyToPlay
        statusObserver = avPlayer.currentItem?.observe(\.status, options: [.new]) { item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    isBuffering = false
                    self.refreshResolvedDuration(from: item)
                    self.logger.info("readyToPlay，时长: \(String(format: "%.2fs", self.duration))")
                    self.publishNowPlaying(isPlaying: true)
                case .failed:
                    isBuffering = false
                    let err = item.error
                    self.logger.error("播放失败: \(err?.localizedDescription ?? "未知错误")")
                    if let nsErr = err as NSError? {
                        self.logger.error("domain=\(nsErr.domain) code=\(nsErr.code)")
                        if let underlying = nsErr.userInfo[NSUnderlyingErrorKey] as? NSError {
                            self.logger.error("底层错误: \(underlying.localizedDescription)")
                        }
                    }
                default:
                    break
                }
            }
        }

        // 监听时间
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak avPlayer] time in
            Task { @MainActor in
                let elapsed = NowPlayingController.sanitizedTime(time.seconds)
                currentTime = elapsed
                self.refreshResolvedDuration(from: avPlayer?.currentItem)
                NowPlayingController.shared.updatePlaybackProgress(
                    elapsed: elapsed,
                    duration: duration,
                    isPlaying: isPlaying
                )
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
                case .autoNext:
                    isPlaying = false
                    avPlayer.seek(to: .zero)
                    onVideoEnd()
                }
            }
        }

        // 仅在已有真实时长时立即发布，避免把 1s 占位写进锁屏
        if duration > 0 {
            publishNowPlaying(isPlaying: true)
        }
        loadArtworkIntoNowPlaying()
        // 流媒体：并行从 asset 拉时长，覆盖 indefinite duration
        Task {
            let assetDur = await MediaDurationResolver.loadAssetDuration(url: url)
            await MainActor.run {
                if assetDur > 0, assetDur > duration {
                    duration = assetDur
                    publishNowPlaying(isPlaying: isPlaying)
                }
            }
        }
        avPlayer.play()
        isPlaying = true
    }

    private func refreshResolvedDuration(from item: AVPlayerItem?) {
        let resolved = MediaDurationResolver.resolve(
            playerItem: item,
            fileDuration: file.duration,
            current: duration
        )
        if resolved > 0 {
            duration = resolved
        }
    }

    private func seekTo(_ position: TimeInterval) {
        let safe = NowPlayingController.sanitizedTime(position)
        currentTime = safe
        player?.seek(to: CMTime(seconds: safe, preferredTimescale: 600))
        NowPlayingController.shared.updatePlaybackProgress(
            elapsed: safe,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    private func publishNowPlaying(isPlaying playing: Bool) {
        NowPlayingController.shared.update(
            title: file.name,
            duration: duration,
            elapsed: currentTime,
            isPlaying: playing
        )
    }

    private func loadArtworkIntoNowPlaying() {
        guard let thumbURL = file.thumbnailURL(apiService: apiService, size: 300) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: thumbURL)
                guard let image = UIImage(data: data) else { return }
                await MainActor.run {
                    NowPlayingController.shared.update(
                        title: file.name,
                        duration: duration,
                        elapsed: currentTime,
                        isPlaying: isPlaying,
                        artworkImage: image
                    )
                }
            } catch {
                // 无封面不阻断播放
            }
        }
    }

    private func cleanupPlayer() {
        statusObserver?.invalidate()
        statusObserver = nil
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

}

// MARK: - AudioPreviewContent

/// 音频播放预览
struct AudioPreviewContent: View {

    @EnvironmentObject private var logger: PreviewLogger

    let file: FileInfo
    let apiService: APIService
    @Binding var isPlaying: Bool
    @Binding var isMuted: Bool
    @Binding var currentTime: Double
    @Binding var showControls: Bool
    let playbackMode: PlaybackMode
    let onAudioEnd: () -> Void
    let onTap: () -> Void

    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var timeObserver: Any?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var coverLoaded = false

    var body: some View {
        ZStack {
            // 音频可视化区域
            VStack(spacing: AppTheme.Spacing.xl) {
                Spacer()

                // 封面图或音乐图标
                if let coverURL = file.thumbnailURL(apiService: apiService, size: 600) {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 280, maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.4), radius: 20)
                        case .failure:
                            Image(systemName: "music.note")
                                .font(.system(size: 80, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.6))
                        default:
                            Image(systemName: "music.note")
                                .font(.system(size: 80, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 80, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.6))
                }

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

                Spacer()

                // 进度条 + 时间（始终显示，不跟随控制栏显隐）
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
                .padding(.bottom, 100) // 给底部控制栏留空间
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onAppear { setupPlayer() }
        .onDisappear { cleanupPlayer() }
        .onChange(of: isPlaying) { _, newValue in
            guard let player = player else { return }
            if newValue {
                player.play()
            } else {
                player.pause()
            }
            NowPlayingController.shared.updatePlaybackProgress(
                elapsed: currentTime,
                duration: duration,
                isPlaying: newValue
            )
        }
        .onChange(of: isMuted) { _, newValue in
            player?.isMuted = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .nowPlayingRemoteSeek)) { note in
            guard let position = note.userInfo?[NowPlayingController.seekPositionKey] as? TimeInterval else { return }
            seekTo(position)
        }
    }

    // MARK: - 播放器管理

    private func setupPlayer() {
        let url: URL? = if let uuid = file.uuid {
            apiService.preview.getContentURL(
                uuid: uuid,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        } else {
            apiService.preview.getContentURL(
                for: file.path,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        }
        guard let url else { return }

        NowPlayingController.shared.activatePlaybackSession()

        duration = MediaDurationResolver.resolve(
            playerItem: nil,
            fileDuration: file.duration,
            current: 0
        )
        logger.info("音频 URL: \(url.absoluteString)")
        let avPlayer = AVPlayer(url: url)
        avPlayer.isMuted = isMuted
        player = avPlayer

        NowPlayingController.shared.onSeek = { [weak avPlayer] position in
            avPlayer?.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }

        statusObserver = avPlayer.currentItem?.observe(\.status, options: [.new]) { item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self.refreshResolvedDuration(from: item)
                    self.logger.info("音频 readyToPlay，时长: \(String(format: "%.2fs", self.duration))")
                    self.publishNowPlaying(isPlaying: true)
                case .failed:
                    let err = item.error
                    self.logger.error("音频加载失败: \(err?.localizedDescription ?? "未知")")
                    if let nsErr = err as NSError? {
                        self.logger.error("domain=\(nsErr.domain) code=\(nsErr.code)")
                        if let underlying = nsErr.userInfo[NSUnderlyingErrorKey] as? NSError {
                            self.logger.error("底层错误: \(underlying.localizedDescription)")
                        }
                    }
                default: break
                }
            }
        }

        // 监听时间
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak avPlayer] time in
            Task { @MainActor in
                let elapsed = NowPlayingController.sanitizedTime(time.seconds)
                currentTime = elapsed
                self.refreshResolvedDuration(from: avPlayer?.currentItem)
                NowPlayingController.shared.updatePlaybackProgress(
                    elapsed: elapsed,
                    duration: duration,
                    isPlaying: isPlaying
                )
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
                case .autoNext:
                    isPlaying = false
                    avPlayer.seek(to: .zero)
                    onAudioEnd()
                }
            }
        }

        if duration > 0 {
            publishNowPlaying(isPlaying: true)
        }
        loadArtworkIntoNowPlaying()
        Task {
            let assetDur = await MediaDurationResolver.loadAssetDuration(url: url)
            await MainActor.run {
                if assetDur > 0, assetDur > duration {
                    duration = assetDur
                    publishNowPlaying(isPlaying: isPlaying)
                }
            }
        }
        avPlayer.play()
        isPlaying = true
    }

    private func refreshResolvedDuration(from item: AVPlayerItem?) {
        let resolved = MediaDurationResolver.resolve(
            playerItem: item,
            fileDuration: file.duration,
            current: duration
        )
        if resolved > 0 {
            duration = resolved
        }
    }

    private func seekTo(_ position: TimeInterval) {
        let safe = NowPlayingController.sanitizedTime(position)
        currentTime = safe
        player?.seek(to: CMTime(seconds: safe, preferredTimescale: 600))
        NowPlayingController.shared.updatePlaybackProgress(
            elapsed: safe,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    private func publishNowPlaying(isPlaying playing: Bool) {
        NowPlayingController.shared.update(
            title: file.name,
            duration: duration,
            elapsed: currentTime,
            isPlaying: playing
        )
    }

    private func loadArtworkIntoNowPlaying() {
        guard let thumbURL = file.thumbnailURL(apiService: apiService, size: 300) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: thumbURL)
                guard let image = UIImage(data: data) else { return }
                await MainActor.run {
                    NowPlayingController.shared.update(
                        title: file.name,
                        duration: duration,
                        elapsed: currentTime,
                        isPlaying: isPlaying,
                        artworkImage: image
                    )
                }
            } catch {}
        }
    }

    private func cleanupPlayer() {
        statusObserver?.invalidate()
        statusObserver = nil
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
        timeObserver = nil
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - PDFPreviewContent

/// PDF 文档预览（使用 PDFKit）
struct PDFPreviewContent: View {

    let file: FileInfo
    let apiService: APIService
    let onTap: () -> Void

    @State private var pdfDocument: PDFDocument?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ZStack {
            if isLoading {
                VStack(spacing: AppTheme.Spacing.lg) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("加载 PDF...")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else if let error = loadError {
                VStack(spacing: AppTheme.Spacing.lg) {
                    Image(systemName: "doc.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else if let document = pdfDocument {
                PDFKitView(document: document)
                    .ignoresSafeArea()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .task {
            await loadPDF()
        }
    }

    private func loadPDF() async {
        let url: URL? = if let uuid = file.uuid {
            apiService.preview.getContentURL(
                uuid: uuid,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        } else {
            apiService.preview.getContentURL(
                for: file.path,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        }
        guard let url else {
            loadError = "无法获取文件地址"
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let document = PDFDocument(data: data) {
                pdfDocument = document
            } else {
                loadError = "PDF 文件无法解析"
            }
        } catch {
            loadError = "加载失败: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

// MARK: - PDFKitView

/// PDFKit 的 UIViewRepresentable 包装
struct PDFKitView: UIViewRepresentable {

    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .black
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {}
}

// MARK: - OtherFilePreviewContent

/// 非媒体文件展示
struct OtherFilePreviewContent: View {

    let file: FileInfo
    let onTap: () -> Void

    private var iconInfo: FileIconInfo {
        FileIconHelper.iconInfo(for: file)
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            // 文件图标
            Image(systemName: iconInfo.icon)
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(iconInfo.color.opacity(0.7))

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

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? PlayerUIView else { return }
        // player 变化时同步更新 playerLayer，否则切换文件后画面不更新
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }

    /// 内部 UIView，承载 AVPlayerLayer
    private class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - SystemVolumeControlView

/// 嵌入隐藏的 MPVolumeView，实现系统音量的读写与监听。
/// 必须添加到视图层级中才能生效（frame 极小，opacity 极低，不影响视觉）。
private struct SystemVolumeControlView: UIViewRepresentable {

    @Binding var volume: Float

    // MARK: Coordinator - KVO 监听系统音量变化

    final class Coordinator: NSObject, @unchecked Sendable {
        var binding: Binding<Float>
        var observation: NSKeyValueObservation?

        init(binding: Binding<Float>) {
            self.binding = binding
        }

        func startObserving() {
            observation = AVAudioSession.sharedInstance().observe(
                \.outputVolume, options: [.new]
            ) { [weak self] _, change in
                guard let self, let newValue = change.newValue else { return }
                DispatchQueue.main.async {
                    self.binding.wrappedValue = newValue
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(binding: $volume)
        try? AVAudioSession.sharedInstance().setActive(true)
        coordinator.startObserving()
        return coordinator
    }

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.alpha = 0.001              // 完全透明但仍在层级中
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        // 通过内部 UISlider 写入系统音量
        if let slider = uiView.subviews.compactMap({ $0 as? UISlider }).first {
            if abs(slider.value - volume) > 0.01 {
                slider.value = volume
            }
        }
    }
}

// MARK: - Preview

// MARK: - DebugLogSheet

struct DebugLogSheet: View {
    @ObservedObject var logger: PreviewLogger
    let fileName: String

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if logger.entries.isEmpty {
                        Text("暂无日志")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(logger.entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.timeString)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .fixedSize()

                                Text(entry.level.rawValue)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(levelColor(entry.level))
                                    .fixedSize()

                                Text(entry.message)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("调试日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = "[\(fileName)]\n" + logger.fullText
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        logger.clear()
                    } label: {
                        Label("清空", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func levelColor(_ level: PreviewLogger.Level) -> Color {
        switch level {
        case .info:    return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }
}

#Preview {
    let server = Server(name: "Test", baseURL: "http://localhost:1234", apiKey: "test")
    if let api = APIService.create(for: server) {
        FilePreviewView(
            apiService: api,
            uuid: "test",
            folderPath: "/tmp"
        )
    }
}
