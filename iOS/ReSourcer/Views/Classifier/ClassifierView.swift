//
//  ClassifierView.swift
//  ReSourcer
//
//  分类页面 - 快速分类文件到不同文件夹
//

import SwiftUI
import AVFoundation
import PDFKit

struct ClassifierView: View {

    // MARK: - Properties

    let apiService: APIService

    @State private var files: [FileInfo] = []
    @State private var categories: [FolderInfo] = []
    @State private var currentIndex = 0
    @State private var sourceFolder: String = ""
    @State private var isLoading = false
    @State private var showSettings = false

    // 文件信息面板
    @State private var showInfoSheet = false
    @State private var showRenameAlert = false
    @State private var renameText = ""

    // 标签
    @State private var fileInfoTags: [Tag] = []
    @State private var showTagEditor = false

    // 已分类计数
    @State private var classifiedCount = 0
    @State private var totalCount = 0

    // 操作历史（用于撤销）
    @State private var operationHistory: [ClassifyOperation] = []

    // 新增文件夹
    @State private var showAddFolder = false
    @State private var newFolderName = ""

    // 排序
    @State private var showReorder = false

    // 预览模式（缩略图 / 原图）
    @State private var useThumbnail = true

    // 预览缩放
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero

    // 长按显示文件名
    @State private var showFileName = false

    // 视频播放器（原图模式）
    @State private var videoPlayer: AVPlayer?

    // 分类选择器高度状态
    @State private var selectorHeight: CGFloat = 150  // 默认收起高度
    private let minHeight: CGFloat = 150  // 最小高度（水平模式）
    private let maxHeight: CGFloat = 400  // 最大高度

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                // 内容区域
                if isLoading {
                    loadingView
                } else if files.isEmpty {
                    emptyView
                } else {
                    classifierContent
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // 撤销按钮
                    Button {
                        undoLastOperation()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(operationHistory.isEmpty)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    // 跳过按钮
                    Button {
                        skipCurrentFile()
                    } label: {
                        Image(systemName: "forward")
                    }
                    .disabled(currentFile == nil)

                    // 文件详情按钮（点击查看信息 / 长按快速显示文件名）
                    Image(systemName: "info.circle")
                        .foregroundStyle(currentFile != nil ? .primary : .tertiary)
                        .onTapGesture {
                            if let file = currentFile {
                                fileInfoTags = []
                                showInfoSheet = true
                                if let uuid = file.uuid {
                                    Task {
                                        fileInfoTags = (try? await apiService.tag.getFileTags(fileUuid: uuid)) ?? []
                                    }
                                }
                            }
                        }
                        .onLongPressGesture(minimumDuration: .infinity, pressing: { isPressing in
                            showFileName = isPressing && currentFile != nil
                        }, perform: {})

                    // 刷新
                    Button {
                        Task { await loadData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        // 标签编辑器
        .sheet(isPresented: $showTagEditor) {
            if let file = currentFile, let uuid = file.uuid {
                TagEditorView(
                    apiService: apiService,
                    sourceFolder: sourceFolder,
                    fileUuid: uuid,
                    onDismiss: { updatedTags in
                        fileInfoTags = updatedTags
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
        // 文件信息面板
        .glassBottomSheet(isPresented: $showInfoSheet, title: "文件信息") {
            if let file = currentFile {
                FileInfoSheetContent(
                    file: file,
                    bottomSpacing: 60,
                    tags: fileInfoTags,
                    onAddTag: file.uuid != nil ? {
                        showInfoSheet = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            showTagEditor = true
                        }
                    } : nil,
                    onRename: {
                        showInfoSheet = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            renameText = file.baseName
                            showRenameAlert = true
                        }
                    }
                )
            }
        }
        // 重命名面板
        .glassBottomSheet(isPresented: $showRenameAlert, title: "重命名") {
            VStack(spacing: AppTheme.Spacing.lg) {
                HStack {
                    TextField("文件名", text: $renameText)
                        .textFieldStyle(.plain)
                    Text(currentFile?.extension ?? "")
                        .foregroundStyle(.tertiary)
                }
                .padding(AppTheme.Spacing.md)
                .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))

                HStack(spacing: AppTheme.Spacing.md) {
                    GlassButton(icon: "trash", style: .secondary, size: .medium) {
                        renameText = ""
                    }
                    .frame(maxWidth: .infinity)

                    GlassButton(icon: "checkmark", style: .primary, size: .medium) {
                        renameCurrentFile()
                    }
                    .disabled(renameText.isEmpty || renameText == currentFile?.baseName)
                    .frame(maxWidth: .infinity)

                    GlassButton(icon: "xmark", style: .secondary, size: .medium) {
                        showRenameAlert = false
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer().frame(height: 60)
            }
            .padding(.vertical, AppTheme.Spacing.md)
        }
        .sheet(isPresented: $showReorder) {
            reorderSheet
        }
        .alert("新建分类文件夹", isPresented: $showAddFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) {
                newFolderName = ""
            }
            Button("创建") {
                createFolder()
            }
            .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Current File

    private var currentFile: FileInfo? {
        guard currentIndex < files.count else { return nil }
        return files[currentIndex]
    }

    // 是否为水平模式（收起状态）
    private var isHorizontalMode: Bool {
        selectorHeight <= minHeight
    }

    // MARK: - Classifier Content

    private var classifierContent: some View {
        VStack(spacing: 0) {
            // 文件预览区域（支持双指缩放）
            ZStack {
                filePreviewSection
                    .scaleEffect(scale)
                    .offset(currentOffset)
            }
            .frame(maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .gesture(pinchGesture)
            .simultaneousGesture(scale > 1.0 ? zoomDragGesture : nil)
            .onTapGesture(count: 2) { toggleZoom() }
                // 长按 info 按钮时浮动显示文件名
                .overlay(alignment: .top) {
                    if showFileName, let name = currentFile?.name {
                        Text(name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassBackground(in: Capsule())
                            .padding(.top, AppTheme.Spacing.md)
                            .transition(.opacity)
                    }
                }
                .animation(AppTheme.Animation.standard, value: showFileName)

            // 分类进度条
            classifyProgressBar
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.sm)

            // 可拖动的分类选择器（浮动卡片风格，与 tab bar 视觉统一）
            draggableCategorySelector
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.sm)
        }
        // 切换文件或切换模式时管理视频/音频播放器 + 重置缩放
        .onChange(of: currentIndex) { _, _ in
            resetZoom()
            if !useThumbnail, let file = currentFile, (file.isVideo || file.isAudio) {
                setupVideoPlayer(for: file)
            } else {
                cleanupVideoPlayer()
            }
        }
        .onChange(of: useThumbnail) { _, newValue in
            resetZoom()
            if !newValue, let file = currentFile, (file.isVideo || file.isAudio) {
                setupVideoPlayer(for: file)
            } else {
                cleanupVideoPlayer()
            }
        }
    }

    // MARK: - File Preview Section

    @ViewBuilder
    private var filePreviewSection: some View {
        if let file = currentFile {
            if !useThumbnail && file.isVideo {
                // 原图模式 + 视频 → 视频播放器
                ZStack {
                    if let player = videoPlayer {
                        AVPlayerView(player: player)
                            .cornerRadius(AppTheme.CornerRadius.lg)
                    } else {
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg)
                            .fill(Color.white.opacity(0.1))
                            .overlay {
                                ProgressView()
                                    .tint(.white)
                            }
                    }

                    // 点击暂停/播放
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if videoPlayer?.rate == 0 {
                                videoPlayer?.play()
                            } else {
                                videoPlayer?.pause()
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
                .onAppear { setupVideoPlayer(for: file) }
                .onDisappear { cleanupVideoPlayer() }
            } else if !useThumbnail && file.isAudio {
                // 原图模式 + 音频 → 音频播放器
                ZStack {
                    if let player = videoPlayer {
                        // 音频可视化占位
                        VStack(spacing: AppTheme.Spacing.lg) {
                            Image(systemName: "music.note")
                                .font(.system(size: 64, weight: .ultraLight))
                                .foregroundStyle(.secondary)
                            Text(file.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // 点击暂停/播放
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if player.rate == 0 {
                                    player.play()
                                } else {
                                    player.pause()
                                }
                            }
                    } else {
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg)
                            .fill(Color.white.opacity(0.1))
                            .overlay {
                                ProgressView()
                                    .tint(.white)
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
                .onAppear { setupVideoPlayer(for: file) }
                .onDisappear { cleanupVideoPlayer() }
            } else if !useThumbnail && file.isPdf {
                // 原图模式 + PDF → PDFKit 预览
                ClassifierPDFPreview(file: file, apiService: apiService)
                    .cornerRadius(AppTheme.CornerRadius.lg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.md)
            } else if file.isAudio {
                // 缩略图模式 + 音频 → 音乐图标占位
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text(file.name)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
            } else if file.isPdf {
                // 缩略图模式 + PDF → 文档图标占位
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text(file.name)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
            } else {
                // 缩略图模式 / 非视频原图（图片/GIF/其他有缩略图的文件）
                let previewURL: URL? = if useThumbnail || file.isVideo {
                    file.thumbnailURL(apiService: apiService, size: 600)
                } else if let uuid = file.uuid {
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

                CachedThumbnailView(url: previewURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(AppTheme.CornerRadius.lg)
                } placeholder: {
                    VStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: file.isVideo ? "film" : "photo")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
            }
        }
    }

    // MARK: - Classify Progress Bar

    private var classifyProgressBar: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            // 缩略图/原图切换
            HStack {
                Spacer()

                Button {
                    GlassAlertManager.shared.showQuickLoading()
                    withAnimation { useThumbnail.toggle() }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        GlassAlertManager.shared.hideQuickLoading()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: useThumbnail ? "photo" : "photo.fill")
                            .font(.caption)
                        Text(useThumbnail ? "缩略图" : "原图")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .interactiveGlassBackground(in: Capsule())
            }

            // 进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // 背景轨道
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))

                    // 已完成进度
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: totalCount > 0
                            ? geo.size.width * CGFloat(classifiedCount) / CGFloat(totalCount)
                            : 0
                        )
                        .animation(AppTheme.Animation.spring, value: classifiedCount)
                }
            }
            .frame(height: 6)

            // 进度文字
            HStack {
                Text("\(classifiedCount) / \(totalCount)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                if totalCount > 0 {
                    Text("\(Int(Double(classifiedCount) / Double(totalCount) * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Draggable Category Selector

    private var draggableCategorySelector: some View {
        VStack(spacing: 0) {
            // 拖动把手
            dragHandle

            // 分类列表内容
            if isHorizontalMode {
                horizontalCategoryList
            } else {
                verticalCategoryList
            }
        }
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 4)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    let newHeight = selectorHeight - value.translation.height
                    selectorHeight = min(max(newHeight, minHeight), maxHeight)
                }
        )
    }

    // MARK: - Horizontal Category List（收起模式）

    private var horizontalCategoryList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(categories) { category in
                    compactCategoryButton(for: category)
                }

                // 添加按钮
                compactAddButton

                // 排序按钮
                compactSortButton
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.md)
        }
    }

    // MARK: - Vertical Category List（展开模式）

    private var verticalCategoryList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Spacing.sm) {
                ForEach(categories) { category in
                    fullCategoryButton(for: category)
                }

                // 操作按钮行
                HStack(spacing: AppTheme.Spacing.sm) {
                    fullAddButton
                    fullSortButton
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .frame(height: selectorHeight - 40) // 减去把手高度
    }

    // MARK: - Compact Category Button（水平滑动用）

    private func compactCategoryButton(for category: FolderInfo) -> some View {
        Button {
            classifyToCategory(category)
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text(category.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("\(category.fileCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: .capsule)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .interactiveGlassBackground(in: Capsule())
    }

    // MARK: - Full Category Button（垂直列表用）

    private func fullCategoryButton(for category: FolderInfo) -> some View {
        Button {
            classifyToCategory(category)
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)

                Text(category.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(category.fileCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1), in: .capsule)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .interactiveGlassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
    }

    // MARK: - Add Buttons

    private var compactAddButton: some View {
        Button {
            newFolderName = ""
            showAddFolder = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                    .font(.subheadline)
                Text("添加")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .interactiveGlassBackground(in: Capsule())
    }

    private var fullAddButton: some View {
        Button {
            newFolderName = ""
            showAddFolder = true
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "plus.circle")
                    .font(.title3)

                Text("添加")
                    .font(.body)
                    .fontWeight(.semibold)

                Spacer()
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .interactiveGlassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
    }

    // MARK: - Sort Buttons

    private var compactSortButton: some View {
        Button {
            showReorder = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.subheadline)
                Text("排序")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .interactiveGlassBackground(in: Capsule())
    }

    private var fullSortButton: some View {
        Button {
            showReorder = true
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.title3)

                Text("排序")
                    .font(.body)
                    .fontWeight(.semibold)

                Spacer()
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .interactiveGlassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
    }

    // MARK: - Reorder Sheet

    private var reorderSheet: some View {
        NavigationStack {
            List {
                ForEach(categories) { category in
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.yellow)
                        Text(category.name)
                            .font(.body)
                        Spacer()
                        Text("\(category.fileCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onMove { from, to in
                    categories.move(fromOffsets: from, toOffset: to)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("调整排序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        saveCategoryOrder()
                        showReorder = false
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showReorder = false
                        // 取消时重新加载恢复原顺序
                        Task { await loadData() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Empty View

    private var emptyView: some View {
        GlassEmptyView(
            icon: "checkmark.circle",
            title: "分类完成",
            message: "所有文件都已分类完毕",
            actionTitle: "刷新"
        ) {
            Task { await loadData() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        GlassLoadingView("加载中...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Preview Zoom

    private var currentOffset: CGSize {
        CGSize(
            width: lastOffset.width + dragTranslation.width,
            height: lastOffset.height + dragTranslation.height
        )
    }

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

    private var zoomDragGesture: some Gesture {
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

    private func toggleZoom() {
        withAnimation(AppTheme.Animation.spring) {
            if scale > 1.0 {
                scale = 1.0
                lastScale = 1.0
                lastOffset = .zero
            } else {
                scale = 2.0
                lastScale = 2.0
            }
        }
    }

    private func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        lastOffset = .zero
    }

    // MARK: - Video Player

    private func setupVideoPlayer(for file: FileInfo) {
        cleanupVideoPlayer()
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

        let player = AVPlayer(url: url)
        videoPlayer = player
        player.play()

        // 播放结束后循环
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
    }

    private func cleanupVideoPlayer() {
        videoPlayer?.pause()
        videoPlayer = nil
    }

    // MARK: - Methods

    /// 当前工作目录（从全局导航状态获取）
    private var currentPath: String {
        let nav = NavigationState.shared
        return nav.currentFolderPath.isEmpty ? sourceFolder : nav.currentFolderPath
    }

    private func loadData() async {
        isLoading = true

        do {
            // 获取配置状态
            let configState = try await apiService.config.getConfigState()
            sourceFolder = configState.sourceFolder

            let workPath = currentPath

            // 获取待分类文件（使用 indexer 分页 API，一次最多 500 条）
            let response = try await apiService.preview.getFilesPaginated(
                in: workPath, offset: 0, limit: 500)
            let ignoredFileNames = LocalStorageService.shared.getAppSettings().ignoredFiles
            files = response.files.map { $0.toFileInfo() }
                .filter { file in !ignoredFileNames.contains(file.name) }

            // 获取分类子文件夹（使用 indexer API）
            let indexed = try await apiService.preview.getIndexedFolders(
                parentPath: workPath, sourceFolder: sourceFolder)
            categories = indexed.map {
                FolderInfo(name: $0.name, hidden: false, fileCount: Int($0.fileCount))
            }

            currentIndex = 0
            classifiedCount = 0
            totalCount = files.count
            operationHistory = []

        } catch {
            GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
        }

        isLoading = false
    }

    private func classifyToCategory(_ category: FolderInfo) {
        guard let file = currentFile, let uuid = file.uuid else { return }

        GlassAlertManager.shared.showQuickLoading()
        Task {
            do {
                let targetPath = "\(currentPath)/\(category.name)"
                _ = try await apiService.file.moveFile(uuid: uuid, to: targetPath)

                GlassAlertManager.shared.hideQuickLoading()

                // 记录操作历史（UUID 不变，撤销时仍可用）
                let operation = ClassifyOperation(
                    file: file,
                    fromIndex: currentIndex,
                    toCategory: category.name
                )
                operationHistory.append(operation)

                // 更新目标文件夹计数 +1
                if let idx = categories.firstIndex(where: { $0.name == category.name }) {
                    categories[idx] = categories[idx].with(fileCount: categories[idx].fileCount + 1)
                }

                // 直接移动到下一个文件，不弹窗
                withAnimation(AppTheme.Animation.bouncy) {
                    classifiedCount += 1
                    currentIndex += 1
                }

            } catch {
                GlassAlertManager.shared.hideQuickLoading()
                GlassAlertManager.shared.showError("分类失败", message: error.localizedDescription)
            }
        }
    }

    private func skipCurrentFile() {
        guard currentFile != nil else { return }

        GlassAlertManager.shared.showQuickLoading()
        withAnimation(AppTheme.Animation.bouncy) {
            currentIndex += 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            GlassAlertManager.shared.hideQuickLoading()
        }
    }

    private func renameCurrentFile() {
        guard let file = currentFile, let uuid = file.uuid,
              !renameText.isEmpty, renameText != file.baseName else { return }

        let newName = renameText + file.extension
        Task {
            do {
                let response = try await apiService.file.renameFile(uuid: uuid, to: newName)
                // 更新本地文件列表中的路径
                if let idx = files.firstIndex(where: { $0.id == file.id }) {
                    files[idx] = FileInfo(
                        uuid: file.uuid,
                        name: newName,
                        path: response.newPath,
                        fileType: file.fileType,
                        extension: file.extension,
                        size: file.size,
                        created: file.created,
                        modified: file.modified,
                        width: file.width,
                        height: file.height,
                        duration: file.duration,
                        sourceUrl: file.sourceUrl
                    )
                }
                showRenameAlert = false
            } catch {
                GlassAlertManager.shared.showError("重命名失败", message: error.localizedDescription)
            }
        }
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        Task {
            do {
                _ = try await apiService.folder.createFolder(name: name)
                newFolderName = ""
                // 刷新分类列表（使用 indexer API）
                let indexed = try await apiService.preview.getIndexedFolders(
                    parentPath: currentPath, sourceFolder: sourceFolder)
                categories = indexed.map {
                    FolderInfo(name: $0.name, hidden: false, fileCount: Int($0.fileCount))
                }
            } catch {
                GlassAlertManager.shared.showError("创建失败", message: error.localizedDescription)
            }
        }
    }

    private func saveCategoryOrder() {
        let order = categories.map(\.name)
        Task {
            do {
                try await apiService.folder.saveFolderOrder(folderPath: currentPath, order: order)
            } catch {
                GlassAlertManager.shared.showError("保存排序失败", message: error.localizedDescription)
            }
        }
    }

    private func undoLastOperation() {
        guard let lastOp = operationHistory.popLast() else { return }

        Task {
            do {
                // 移回原位置（UUID 不变，文件移动后仍有效）
                _ = try await apiService.file.moveFile(uuid: lastOp.file.uuid!, to: currentPath)

                // 恢复目标文件夹计数 -1
                if let idx = categories.firstIndex(where: { $0.name == lastOp.toCategory }) {
                    categories[idx] = categories[idx].with(fileCount: max(0, categories[idx].fileCount - 1))
                }

                // 恢复索引，不弹窗
                withAnimation(AppTheme.Animation.bouncy) {
                    classifiedCount = max(0, classifiedCount - 1)
                    currentIndex = lastOp.fromIndex
                }

            } catch {
                GlassAlertManager.shared.showError("撤销失败", message: error.localizedDescription)
                // 恢复操作历史
                operationHistory.append(lastOp)
            }
        }
    }
}

// MARK: - ClassifierPDFPreview

/// 分类器中的 PDF 预览（简化版）
struct ClassifierPDFPreview: View {
    let file: FileInfo
    let apiService: APIService

    @State private var pdfDocument: PDFDocument?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let document = pdfDocument {
                PDFKitView(document: document)
            } else {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("PDF 加载失败")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .task {
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
                isLoading = false
                return
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                pdfDocument = PDFDocument(data: data)
            } catch {}
            isLoading = false
        }
    }
}

// MARK: - Classify Operation

/// 分类操作记录（用于撤销，UUID 不变所以不需要记录 newPath）
struct ClassifyOperation {
    let file: FileInfo
    let fromIndex: Int
    let toCategory: String
}

// MARK: - Preview

#Preview {
    let server = Server(name: "Test", baseURL: "http://localhost:1234", apiKey: "test")
    if let api = APIService.create(for: server) {
        ClassifierView(apiService: api)
            .previewWithGlassBackground()
    }
}
