//
//  GalleryView.swift
//  ReSourcer
//
//  首页 - 画廊视图
//

import SwiftUI
import PhotosUI
import Photos

struct GalleryView: View {

    // MARK: - Properties

    let apiService: APIService

    @State private var sourceFolder = ""
    @State private var sourceFolderFileCount = 0
    @State private var currentFolderFullPath = ""        // 当前浏览的完整文件夹路径
    @State private var subfolders: [IndexedFolder] = []  // 当前层的子文件夹
    @State private var breadcrumb: [BreadcrumbItem] = [] // 面包屑路径
    @State private var files: [FileInfo] = []
    @State private var isLoading = false

    // 分页状态
    @State private var filesOffset = 0
    @State private var hasMoreFiles = true
    @State private var isLoadingMore = false
    @State private var filesTotalCount = 0
    private let filesPageSize = 100

    // 下拉菜单状态
    @State private var isDropdownOpen = false

    // 显示模式
    @State private var viewMode: GalleryViewMode = .grid
    /// 每个网格单元格的最小宽度，SwiftUI 根据屏幕宽度自动计算列数
    private let gridItemMinWidth: CGFloat = 120

    // 导航
    @State private var navPath = NavigationPath()

    // 文件信息弹窗
    @State private var selectedFile: FileInfo?       // 用于重命名/移动操作
    @State private var fileInfoToShow: FileInfo?     // 驱动弹窗显示 + 数据（单一状态源）
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showMoveSheet = false


    // 上传相关
    @State private var showPhotoPicker = false
    @State private var showUploadConfirm = false
    @State private var pickerResults: [PHPickerResult] = []
    @State private var showUploadTaskList = false

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack(alignment: .top) {
                // 主内容区域
                Group {
                    if !files.isEmpty {
                        contentView
                    } else if !isLoading {
                        emptyView
                    }
                }
                .padding(.top, 70) // 给顶部浮动栏留空间

                // 遮罩层
                if isDropdownOpen {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isDropdownOpen = false
                            }
                        }
                }

                // 顶部浮动栏
                VStack(spacing: 0) {
                    floatingHeader
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.top, AppTheme.Spacing.md)

                    // 下拉菜单
                    if isDropdownOpen {
                        folderDropdown
                            .padding(.horizontal, AppTheme.Spacing.lg)
                            .padding(.top, AppTheme.Spacing.sm)
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                    }

                    Spacer()
                }
            }
            // 右下角悬浮上传按钮
            .overlay(alignment: .bottomTrailing) {
                Button {
                    requestPhotoAccessAndShowPicker()
                } label: {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(width: 56, height: 56)
                        .background(Color.primary)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                }
                .padding(.trailing, AppTheme.Spacing.lg)
                .padding(.bottom, 16)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Int.self) { index in
                FilePreviewView(
                    apiService: apiService,
                    files: files,
                    initialIndex: index,
                    hasMore: hasMoreFiles,
                    onLoadMore: {
                        await loadMoreForPreview()
                    }
                )
            }
            .navigationDestination(isPresented: $showUploadTaskList) {
                UploadTaskListView(apiService: apiService)
            }
        }
        .task {
            await loadInitial()
        }
        // 监听源文件夹切换：清空当前状态，重新加载新源文件夹
        .onReceive(NotificationCenter.default.publisher(for: .sourceFolderDidChange)) { _ in
            files = []
            subfolders = []
            breadcrumb = []
            currentFolderFullPath = ""
            Task {
                await GlassAlertManager.shared.withQuickLoading {
                    await loadInitial()
                }
            }
        }
        // 从其他 tab 切回 Gallery 时，同步本地路径到全局状态
        .onAppear {
            if !sourceFolder.isEmpty {
                NavigationState.shared.setCurrentFolder(currentFolderPath)
            }
        }
        // 文件信息面板
        .glassBottomSheet(
            isPresented: Binding(
                get: { fileInfoToShow != nil },
                set: { if !$0 { fileInfoToShow = nil } }
            ),
            title: "文件信息"
        ) {
            galleryFileInfoContent
        }
        // 重命名面板
        .glassBottomSheet(isPresented: $showRenameAlert, title: "重命名") {
            VStack(spacing: AppTheme.Spacing.lg) {
                HStack {
                    TextField("文件名", text: $renameText)
                        .textFieldStyle(.plain)
                    Text(selectedFile?.extension ?? "")
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
                        Task { await performRename() }
                    }
                    .disabled(renameText.isEmpty || renameText == selectedFile?.baseName)
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
        // 移动面板（使用标准 sheet 确保生命周期正确）
        .sheet(isPresented: $showMoveSheet) {
            MoveSheetView(
                apiService: apiService,
                sourceFolder: sourceFolder,
                file: selectedFile,
                onDismiss: { showMoveSheet = false },
                onMoved: { folderName in
                    showMoveSheet = false
                    GlassAlertManager.shared.showSuccess("已移动到 \(folderName)")
                    await refreshFiles()
                }
            )
            .presentationDetents([.medium, .large])
        }
        // 照片选择器
        .sheet(isPresented: $showPhotoPicker) {
            PHPickerWrapper(
                isPresented: $showPhotoPicker,
                maxSelection: 100
            ) { results in
                pickerResults = results
            }
            .ignoresSafeArea()
        }
        // picker 关闭后延迟显示确认面板，避免时序问题
        // 注意：Swift 6 中 DispatchQueue.main.asyncAfter 不等同于 MainActor，修改 @State 会崩溃
        .onChange(of: showPhotoPicker) { _, isShowing in
            if !isShowing && !pickerResults.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    showUploadConfirm = true
                }
            }
        }
        // 上传确认面板
        .glassBottomSheet(isPresented: $showUploadConfirm) {
            PhotoUploadConfirmView(
                apiService: apiService,
                pickerResults: pickerResults,
                targetFolder: currentFolderPath,
                onUploadStarted: {
                    showUploadConfirm = false
                    pickerResults = []
                    // 留在当前页面，延迟后刷新文件列表
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        await refreshFiles()
                    }
                },
                onCancel: {
                    showUploadConfirm = false
                    pickerResults = []
                }
            )
        }
    }

    // MARK: - Floating Header

    /// 是否不在源文件夹根目录（可以返回上级）
    private var canGoBack: Bool {
        !currentFolderFullPath.isEmpty && currentFolderFullPath != sourceFolder
    }

    /// 当前显示的文件夹名称
    private var currentFolderDisplayName: String {
        if currentFolderFullPath.isEmpty || currentFolderFullPath == sourceFolder {
            return sourceFolderDisplayName
        }
        return currentFolderFullPath.components(separatedBy: "/").last ?? sourceFolderDisplayName
    }

    /// 左划返回上一级
    private func goToParentFolder() {
        guard canGoBack else { return }
        let parent = (currentFolderFullPath as NSString).deletingLastPathComponent
        Task { await navigateToFolder(path: parent) }
    }

    @State private var headerDragOffset: CGFloat = 0

    /// 胶囊内标签：icon + 文件夹名（不含下拉箭头，箭头固定不随滑动）
    private func headerLabel(icon: String, iconColor: Color, name: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)

            Text(name)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.leading, 20)
        .padding(.trailing, 36) // 给固定箭头留空间
        .padding(.vertical, 12)
    }

    /// 上级文件夹名称（用于拖动过渡显示）
    private var parentFolderDisplayName: String {
        let parent = (currentFolderFullPath as NSString).deletingLastPathComponent
        if parent == sourceFolder || parent.isEmpty {
            return sourceFolderDisplayName
        }
        return parent.components(separatedBy: "/").last ?? sourceFolderDisplayName
    }

    private var floatingHeader: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // 文件夹选择器：外壳固定，内容随拖动滑动
            // 用隐藏内容撑出尺寸，可见部分用 overlay 渲染
            headerLabel(
                icon: canGoBack ? "folder.fill" : "folder.fill.badge.gearshape",
                iconColor: canGoBack ? .yellow : .orange,
                name: currentFolderDisplayName
            )
            .opacity(0) // 仅用于占位
            .glassBackground(in: Capsule())
            .overlay {
                GeometryReader { geo in
                    let width = geo.size.width
                    HStack(spacing: 0) {
                        // 上级文件夹（左侧，可见区域外）
                        headerLabel(
                            icon: "folder.fill.badge.gearshape",
                            iconColor: .orange,
                            name: parentFolderDisplayName
                        )
                        .frame(width: width, height: geo.size.height)

                        // 当前文件夹
                        headerLabel(
                            icon: canGoBack ? "folder.fill" : "folder.fill.badge.gearshape",
                            iconColor: canGoBack ? .yellow : .orange,
                            name: currentFolderDisplayName
                        )
                        .frame(width: width, height: geo.size.height)
                    }
                    .offset(x: -width + headerDragOffset)
                }
                .clipShape(Capsule())
            }
            // 固定的下拉箭头（不随内容滑动）
            .overlay(alignment: .trailing) {
                Image(systemName: isDropdownOpen ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 16)
            }
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDropdownOpen.toggle()
                }
            }
            .simultaneousGesture(
                canGoBack ?
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if value.translation.width > 0 {
                            headerDragOffset = value.translation.width * 0.8
                        }
                    }
                    .onEnded { value in
                        if value.translation.width > 80 {
                            // 超过阈值：动画滑到上级位置，结束后导航
                            withAnimation(.easeOut(duration: 0.25)) {
                                headerDragOffset = UIScreen.main.bounds.width
                            } completion: {
                                headerDragOffset = 0
                                goToParentFolder()
                            }
                        } else {
                            // 未达阈值：弹回原位
                            withAnimation(.spring(duration: 0.3)) {
                                headerDragOffset = 0
                            }
                        }
                    }
                : nil
            )

            // 上传记录
            Button {
                showUploadTaskList = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .interactiveGlassBackground(in: Circle())

            // 视图切换按钮
            Button {
                withAnimation {
                    viewMode = viewMode == .grid ? .list : .grid
                }
            } label: {
                Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .interactiveGlassBackground(in: Circle())
        }
    }

    // MARK: - Folder Dropdown

    private var folderDropdown: some View {
        VStack(spacing: 0) {
            // 回到源文件夹（不在根目录时显示）
            if canGoBack {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDropdownOpen = false
                    }
                    Task { await navigateToFolder(path: sourceFolder) }
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "folder.fill.badge.gearshape")
                            .font(.title3)
                            .foregroundStyle(.orange)

                        Text(sourceFolderDisplayName)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text("回到根目录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.horizontal, AppTheme.Spacing.md)
            }

            // 子文件夹列表
            if subfolders.isEmpty {
                HStack {
                    Spacer()
                    Text("当前文件夹没有子文件夹")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, AppTheme.Spacing.lg)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(subfolders) { folder in
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDropdownOpen = false
                                }
                                Task { await navigateToFolder(path: folder.path) }
                            } label: {
                                HStack(spacing: AppTheme.Spacing.md) {
                                    Image(systemName: "folder.fill")
                                        .font(.title3)
                                        .foregroundStyle(.yellow)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.name)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        Text("\(folder.fileCount) 个文件")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, AppTheme.Spacing.md)
                                .padding(.vertical, AppTheme.Spacing.sm)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .padding(AppTheme.Spacing.sm)
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        GeometryReader { geometry in
            ScrollView {
                if viewMode == .grid {
                    gridView(containerWidth: geometry.size.width)
                } else {
                    listView
                }
            }
            .refreshable {
                await GlassAlertManager.shared.withQuickLoading {
                    await refreshFiles()
                }
            }
        }
    }

    // MARK: - Grid View

    /// 网格列数：根据容器宽度动态计算，限制 3~5 列
    private func gridView(containerWidth: CGFloat) -> some View {
        let padding = AppTheme.Spacing.md * 2
        let spacing = AppTheme.Spacing.sm
        let availableWidth = containerWidth - padding
        let rawCount = Int(availableWidth / gridItemMinWidth)
        let columnCount = min(max(rawCount, 3), 5)
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)

        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                Button {
                    openFilePreview(at: index)
                } label: {
                    GalleryGridItem(file: file, apiService: apiService, sourceFolder: sourceFolder)
                }
                .buttonStyle(.plain)
            }

            // 分页加载哨兵
            if hasMoreFiles {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .onAppear { loadMoreFiles() }
            }
        }
        .padding(AppTheme.Spacing.md)
    }

    // MARK: - List View

    private var listView: some View {
        LazyVStack(spacing: AppTheme.Spacing.sm) {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                GalleryListItem(
                    file: file,
                    apiService: apiService,
                    sourceFolder: sourceFolder,
                    onTap: { openFilePreview(at: index) },
                    onInfoTap: {
                        selectedFile = file
                        fileInfoToShow = file
                    }
                )
            }

            // 分页加载哨兵
            if hasMoreFiles {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .onAppear { loadMoreFiles() }
            }
        }
        .padding(AppTheme.Spacing.md)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        GlassEmptyView(
            icon: "folder",
            title: "暂无文件",
            message: "该文件夹中没有文件"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Methods

    /// 源文件夹显示名称
    private var sourceFolderDisplayName: String {
        sourceFolder.components(separatedBy: "/").last ?? "源文件夹"
    }

    /// 当前选中的文件夹完整路径
    private var currentFolderPath: String {
        currentFolderFullPath.isEmpty ? sourceFolder : currentFolderFullPath
    }

    /// 初始加载：获取源文件夹配置 → 导航到源文件夹
    private func loadInitial() async {
        do {
            let configState = try await apiService.config.getConfigState()
            sourceFolder = configState.sourceFolder
            NavigationState.shared.setSourceFolder(sourceFolder)
            await navigateToFolder(path: sourceFolder)
        } catch {
            if !error.isCancelledRequest {
                GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
            }
        }
    }

    /// 统一导航方法：切换到指定文件夹路径
    private func navigateToFolder(path: String) async {
        currentFolderFullPath = path
        NavigationState.shared.setCurrentFolder(path)
        files = []
        isLoading = true
        GlassAlertManager.shared.showQuickLoading()

        // 加载子文件夹
        do {
            subfolders = try await apiService.preview.getIndexedFolders(
                parentPath: path, sourceFolder: sourceFolder)
        } catch {
            subfolders = []
        }

        // 加载面包屑
        do {
            breadcrumb = try await apiService.preview.getBreadcrumb(folderPath: path)
        } catch {
            breadcrumb = [BreadcrumbItem(name: sourceFolderDisplayName, path: sourceFolder)]
        }

        await loadFiles(path: path, reset: true, showLoading: false)
        GlassAlertManager.shared.hideQuickLoading()
        isLoading = false
    }

    private func loadFiles(path: String, reset: Bool = true, showLoading: Bool = true) async {
        if reset {
            filesOffset = 0
            files = []
            hasMoreFiles = true
        }
        if reset && showLoading { isLoading = true; GlassAlertManager.shared.showQuickLoading() }
        do {
            let response = try await apiService.preview.getFilesPaginated(
                in: path, offset: filesOffset, limit: filesPageSize
            )
            let newFiles = response.files.map { $0.toFileInfo() }
            if reset {
                files = newFiles
            } else {
                files.append(contentsOf: newFiles)
            }
            filesOffset += newFiles.count
            hasMoreFiles = response.hasMore
            filesTotalCount = response.total
            // 在源文件夹层级时记录文件总数
            if reset && path == sourceFolder {
                sourceFolderFileCount = response.total
            }
        } catch {
            if !error.isCancelledRequest {
                GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
            }
        }
        if reset && showLoading { GlassAlertManager.shared.hideQuickLoading(); isLoading = false }
    }

    /// 加载更多文件（分页续载）
    private func loadMoreFiles() {
        guard !isLoadingMore && hasMoreFiles else { return }
        isLoadingMore = true
        Task {
            await loadFiles(path: currentFolderPath, reset: false)
            isLoadingMore = false
        }
    }

    /// 供 FilePreviewView 调用的分页加载，返回新增文件
    private func loadMoreForPreview() async -> [FileInfo] {
        guard hasMoreFiles else { return [] }
        do {
            let response = try await apiService.preview.getFilesPaginated(
                in: currentFolderPath, offset: filesOffset, limit: filesPageSize
            )
            let newFiles = response.files.map { $0.toFileInfo() }
            files.append(contentsOf: newFiles)
            filesOffset += newFiles.count
            hasMoreFiles = response.hasMore
            filesTotalCount = response.total
            return newFiles
        } catch {
            return []
        }
    }

    /// 下拉刷新 — 重置分页，从头加载当前文件夹
    private func refreshFiles() async {
        let path = currentFolderPath

        // 并行刷新子文件夹和面包屑（各自独立处理错误）
        async let foldersTask = apiService.preview.getIndexedFolders(
            parentPath: path, sourceFolder: sourceFolder)
        async let breadcrumbTask = apiService.preview.getBreadcrumb(folderPath: path)

        // 重置分页状态并加载文件
        filesOffset = 0
        hasMoreFiles = true

        do {
            let response = try await apiService.preview.getFilesPaginated(
                in: path, offset: 0, limit: filesPageSize
            )
            let newFiles = response.files.map { $0.toFileInfo() }
            files = newFiles
            filesOffset = newFiles.count
            hasMoreFiles = response.hasMore
            filesTotalCount = response.total
            if path == sourceFolder {
                sourceFolderFileCount = response.total
            }
        } catch {
            if !error.isCancelledRequest {
                GlassAlertManager.shared.showError("刷新失败", message: error.localizedDescription)
            }
        }

        // 等待子文件夹和面包屑
        do { subfolders = try await foldersTask } catch { subfolders = [] }
        do { breadcrumb = try await breadcrumbTask } catch {
            breadcrumb = [BreadcrumbItem(name: sourceFolderDisplayName, path: sourceFolder)]
        }
    }

    /// 点击文件打开预览，带 quick loading 反馈
    private func openFilePreview(at index: Int) {
        GlassAlertManager.shared.showQuickLoading()
        navPath.append(index)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            GlassAlertManager.shared.hideQuickLoading()
        }
    }

    /// 检查并请求相册权限，然后显示选择器
    private func requestPhotoAccessAndShowPicker() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .authorized, .limited:
            showPhotoPicker = true
        case .notDetermined:
            Task {
                let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                await MainActor.run {
                    if newStatus == .authorized || newStatus == .limited {
                        showPhotoPicker = true
                    } else {
                        GlassAlertManager.shared.showWarning("需要相册权限", message: "请在设置中允许访问相册")
                    }
                }
            }
        case .denied, .restricted:
            GlassAlertManager.shared.showWarning("需要相册权限", message: "请在设置中允许访问相册")
        @unknown default:
            break
        }
    }

    // MARK: - 文件信息面板内容

    @ViewBuilder
    private var galleryFileInfoContent: some View {
        if let file = fileInfoToShow {
            FileInfoSheetContent(
                file: file,
                bottomSpacing: 60,
                onRename: {
                    fileInfoToShow = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        renameText = selectedFile?.baseName ?? ""
                        showRenameAlert = true
                    }
                },
                onMove: {
                    fileInfoToShow = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        showMoveSheet = true
                    }
                },
                onDownload: {
                    let fileCopy = file
                    fileInfoToShow = nil
                    saveFileToDevice(fileCopy)
                }
            )
        }
    }


    // MARK: - 文件操作


    private func performRename() async {
        guard let file = selectedFile, !renameText.isEmpty else { return }
        let newName = renameText + file.extension
        do {
            _ = try await apiService.file.renameFile(at: file.path, to: newName)
            GlassAlertManager.shared.showSuccess("重命名成功")
            await refreshFiles()
        } catch {
            GlassAlertManager.shared.showError("重命名失败", message: error.localizedDescription)
        }
    }

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

}

// MARK: - View Mode

enum GalleryViewMode {
    case grid
    case list
}

// MARK: - Move Sheet View（标准 .sheet，生命周期可靠）

/// 文件移动面板 — 多级文件夹导航
struct MoveSheetView: View {
    let apiService: APIService
    let sourceFolder: String
    let file: FileInfo?
    let onDismiss: () -> Void
    let onMoved: (String) async -> Void

    @State private var currentPath: String = ""
    @State private var subfolders: [IndexedFolder] = []
    @State private var isLoading = false

    private var displayName: String {
        if currentPath.isEmpty || currentPath == sourceFolder {
            return URL(fileURLWithPath: sourceFolder).lastPathComponent
        }
        return URL(fileURLWithPath: currentPath).lastPathComponent
    }

    private var canGoBack: Bool {
        !currentPath.isEmpty && currentPath != sourceFolder
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 文件夹列表
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if subfolders.isEmpty && !canGoBack {
                    Spacer()
                    Text("没有子文件夹")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List {
                        if canGoBack {
                            // 子文件夹层级：显示 .. 返回上级
                            Button {
                                let parent = (currentPath as NSString).deletingLastPathComponent
                                Task { await loadSubfolders(path: parent) }
                            } label: {
                                HStack(spacing: AppTheme.Spacing.md) {
                                    Image(systemName: "arrowshape.turn.up.left.fill")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)

                                    Text("..")
                                        .font(.body)
                                        .foregroundStyle(.secondary)

                                    Spacer()
                                }
                            }
                        } else {
                            // 源文件夹层级：显示源文件夹名（不可点击）
                            HStack(spacing: AppTheme.Spacing.md) {
                                Image(systemName: "folder.fill.badge.gearshape")
                                    .font(.title3)
                                    .foregroundStyle(.orange)

                                Text(displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                        }

                        // 子文件夹
                        ForEach(subfolders) { folder in
                            Button {
                                Task { await loadSubfolders(path: folder.path) }
                            } label: {
                                HStack(spacing: AppTheme.Spacing.md) {
                                    Image(systemName: "folder.fill")
                                        .font(.title3)
                                        .foregroundStyle(.yellow)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.name)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        Text("\(folder.fileCount) 个文件")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                // 底部「移动至此」按钮
                Button {
                    Task { await moveToPath(currentPath.isEmpty ? sourceFolder : currentPath, name: displayName) }
                } label: {
                    Text("移动至此")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(.blue, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
            }
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onDismiss() }
                }
            }
        }
        .task {
            await loadSubfolders(path: sourceFolder)
        }
    }

    private func loadSubfolders(path: String) async {
        currentPath = path
        isLoading = true
        do {
            let result = try await apiService.preview.getIndexedFolders(
                parentPath: path, sourceFolder: sourceFolder)
            subfolders = result
        } catch {
            subfolders = []
        }
        isLoading = false
    }

    private func moveToPath(_ path: String, name: String) async {
        guard let file else { return }
        do {
            _ = try await apiService.file.moveFile(at: file.path, to: path)
            await onMoved(name)
        } catch {
            GlassAlertManager.shared.showError("移动失败", message: error.localizedDescription)
        }
    }
}

// MARK: - Gallery Grid Item

struct GalleryGridItem: View {
    let file: FileInfo
    let apiService: APIService
    var sourceFolder: String?

    var body: some View {
        // 用 Color.clear 占住正方形尺寸，图片用 overlay 填充后裁切
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                    CachedThumbnailView(
                        url: file.thumbnailURL(apiService: apiService, sourceFolder: sourceFolder)
                    ) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.white.opacity(0.08)
                            .overlay {
                                Image(systemName: gridPlaceholderIcon(for: file))
                                    .font(.title2)
                                    .foregroundStyle(.tertiary)
                            }
                    }
                }
            .overlay {
                // 视频播放图标（居中，液态玻璃风格）
                if file.isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                        .glassBackground(in: Circle())
                }
                // 音频音符图标（居中，与视频播放按钮同尺寸）
                if file.isAudio {
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.4), in: Circle())
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 4) {
                    // 视频时长
                    if file.isVideo, let duration = file.formattedDuration {
                        Text(duration)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .glassBackground(in: Capsule())
                    }

                    // 扩展名标签（所有文件）
                    Text(file.extensionLabel)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassBackground(in: Capsule())
                }
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
            .shadow(color: .white.opacity(0.06), radius: 2, x: 0, y: -1)
    }

    /// 网格占位图标
    private func gridPlaceholderIcon(for file: FileInfo) -> String {
        if file.isVideo { return "film" }
        if file.isAudio { return "music.note" }
        if file.isPdf { return "doc.fill" }
        return "photo"
    }
}

// MARK: - Gallery List Item

struct GalleryListItem: View {
    let file: FileInfo
    let apiService: APIService
    var sourceFolder: String?
    var onTap: (() -> Void)?
    var onInfoTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            // 主内容区域 — 点击进入预览
            Button {
                onTap?()
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    // 缩略图
                    CachedThumbnailView(
                        url: file.thumbnailURL(apiService: apiService, sourceFolder: sourceFolder)
                    ) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: listPlaceholderIcon(for: file))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 60, height: 60)
                    .clipped()
                    .cornerRadius(AppTheme.CornerRadius.sm)

                    // 文件信息
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                        Text(file.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: AppTheme.Spacing.sm) {
                            Text(file.extensionLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text(file.formattedSize)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if let duration = file.formattedDuration {
                                Text(duration)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 更多按钮 — 点击弹出文件信息
            Button {
                onInfoTap?()
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.Spacing.md)
        .clearGlassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
    }

    /// 列表占位图标
    private func listPlaceholderIcon(for file: FileInfo) -> String {
        if file.isVideo { return "film" }
        if file.isAudio { return "music.note" }
        if file.isPdf { return "doc.fill" }
        return "photo"
    }
}

// MARK: - FileInfo 缩略图 URL 辅助

extension FileInfo {
    /// 根据 uuid 是否存在选择缩略图 URL 策略
    @MainActor
    func thumbnailURL(apiService: APIService, size: Int = 300, sourceFolder: String? = nil) -> URL? {
        if let uuid {
            return apiService.preview.getThumbnailURL(
                uuid: uuid, size: size,
                baseURL: apiService.baseURL, apiKey: apiService.apiKey,
                sourceFolder: sourceFolder
            )
        }
        return apiService.preview.getThumbnailURL(
            for: path, size: size,
            baseURL: apiService.baseURL, apiKey: apiService.apiKey
        )
    }
}

// MARK: - Preview

#Preview {
    let server = Server(name: "Test", baseURL: "http://localhost:1234", apiKey: "test")
    if let api = APIService.create(for: server) {
        GalleryView(apiService: api)
            .previewWithGlassBackground()
    }
}
