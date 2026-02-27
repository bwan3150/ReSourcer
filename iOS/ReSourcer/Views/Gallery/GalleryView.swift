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
    @State private var isRefreshing = false
    @State private var filesTotalCount = 0
    private let filesPageSize = 100

    // 下拉菜单状态
    @State private var isDropdownOpen = false

    // 下拉菜单内浏览状态（与 gallery 当前文件夹独立）
    @State private var dropdownBrowsingPath: String = ""
    @State private var dropdownSubfolders: [IndexedFolder] = []
    @State private var isLoadingDropdown = false

    // 浏览器式导航历史
    @State private var historyBack: [String] = []    // 后退栈
    @State private var historyForward: [String] = [] // 前进栈
    @State private var capsuleWidth: CGFloat = 0

    // 下拉菜单内新增/排序
    @State private var showAddFolder = false
    @State private var newFolderName = ""
    @State private var showReorder = false

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
    @State private var fileInfoTags: [Tag] = []
    @State private var showTagEditor = false

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
                    } else {
                        ScrollView {
                            if !isLoading {
                                emptyView
                            }
                        }
                        .refreshable {
                            await GlassAlertManager.shared.withQuickLoading {
                                await refreshFiles()
                            }
                        }
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
            historyBack = []
            historyForward = []
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
                    // 立即从本地数组移除被移动的文件（即时反馈）
                    if let movedFile = selectedFile {
                        files.removeAll { $0.id == movedFile.id }
                    }
                    GlassAlertManager.shared.showSuccess("已移动到 \(folderName)")
                    await refreshFiles()
                }
            )
            .presentationDetents([.medium, .large])
        }
        // 标签编辑器
        .sheet(isPresented: $showTagEditor) {
            if let file = selectedFile, let uuid = file.uuid {
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
        // 新建文件夹弹窗
        .alert("新建文件夹", isPresented: $showAddFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) {
                newFolderName = ""
            }
            Button("创建") {
                createFolderInDropdown()
            }
            .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        // 文件夹排序面板
        .sheet(isPresented: $showReorder) {
            NavigationStack {
                List {
                    ForEach(dropdownSubfolders) { folder in
                        HStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.yellow)
                            Text(folder.name)
                                .font(.body)
                            Spacer()
                            Text("\(folder.fileCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onMove { from, to in
                        dropdownSubfolders.move(fromOffsets: from, toOffset: to)
                    }
                }
                .environment(\.editMode, .constant(.active))
                .navigationTitle("调整排序")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            saveDropdownFolderOrder()
                            showReorder = false
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            showReorder = false
                            // 恢复原顺序
                            Task { await browseInDropdown(path: dropdownBrowsingPath) }
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
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

    /// 后退目标文件夹显示名
    private var backTargetDisplayName: String {
        guard let path = historyBack.last else { return "" }
        if path == sourceFolder { return sourceFolderDisplayName }
        return path.components(separatedBy: "/").last ?? ""
    }

    /// 前进目标文件夹显示名
    private var forwardTargetDisplayName: String {
        guard let path = historyForward.last else { return "" }
        if path == sourceFolder { return sourceFolderDisplayName }
        return path.components(separatedBy: "/").last ?? ""
    }

    /// 下拉菜单当前浏览路径的显示名
    private var dropdownDisplayName: String {
        if dropdownBrowsingPath == sourceFolder || dropdownBrowsingPath.isEmpty {
            return sourceFolderDisplayName
        }
        return dropdownBrowsingPath.components(separatedBy: "/").last ?? ""
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
                        // 后退目标（左侧）
                        Group {
                            if let backPath = historyBack.last {
                                headerLabel(
                                    icon: backPath == sourceFolder ? "folder.fill.badge.gearshape" : "folder.fill",
                                    iconColor: backPath == sourceFolder ? .orange : .yellow,
                                    name: backTargetDisplayName
                                )
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: width, height: geo.size.height)

                        // 当前文件夹
                        headerLabel(
                            icon: canGoBack ? "folder.fill" : "folder.fill.badge.gearshape",
                            iconColor: canGoBack ? .yellow : .orange,
                            name: currentFolderDisplayName
                        )
                        .frame(width: width, height: geo.size.height)

                        // 前进目标（右侧）
                        Group {
                            if let forwardPath = historyForward.last {
                                headerLabel(
                                    icon: forwardPath == sourceFolder ? "folder.fill.badge.gearshape" : "folder.fill",
                                    iconColor: forwardPath == sourceFolder ? .orange : .yellow,
                                    name: forwardTargetDisplayName
                                )
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: width, height: geo.size.height)
                    }
                    .offset(x: -width + headerDragOffset)
                    .onAppear { capsuleWidth = width }
                    .onChange(of: geo.size.width) { _, newWidth in
                        capsuleWidth = newWidth
                    }
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
                if !isDropdownOpen {
                    Task { await browseInDropdown(path: currentFolderFullPath.isEmpty ? sourceFolder : currentFolderFullPath) }
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDropdownOpen.toggle()
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        let dx = value.translation.width
                        if dx > 0 && !historyBack.isEmpty {
                            // 右滑（后退）— 带阻尼
                            headerDragOffset = dx * 0.6
                        } else if dx < 0 && !historyForward.isEmpty {
                            // 左滑（前进）— 带阻尼
                            headerDragOffset = dx * 0.6
                        }
                    }
                    .onEnded { value in
                        let dx = value.translation.width
                        let threshold = capsuleWidth * 0.5

                        if dx > 0 && !historyBack.isEmpty {
                            if dx * 0.6 > threshold {
                                // 超过 50%：滑到位，完成后导航
                                withAnimation(.easeOut(duration: 0.25)) {
                                    headerDragOffset = capsuleWidth
                                } completion: {
                                    headerDragOffset = 0
                                    Task { await goBack() }
                                }
                            } else {
                                // 未达 50%：弹回
                                withAnimation(.spring(duration: 0.3)) {
                                    headerDragOffset = 0
                                }
                            }
                        } else if dx < 0 && !historyForward.isEmpty {
                            if abs(dx * 0.6) > threshold {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    headerDragOffset = -capsuleWidth
                                } completion: {
                                    headerDragOffset = 0
                                    Task { await goForward() }
                                }
                            } else {
                                withAnimation(.spring(duration: 0.3)) {
                                    headerDragOffset = 0
                                }
                            }
                        } else {
                            withAnimation(.spring(duration: 0.3)) {
                                headerDragOffset = 0
                            }
                        }
                    }
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
            // 不在根目录时显示导航辅助行
            if dropdownBrowsingPath != sourceFolder && !dropdownBrowsingPath.isEmpty {
                // 前往当前浏览文件夹 — 将 gallery 导航到下拉菜单当前路径
                Button {
                    let targetPath = dropdownBrowsingPath
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDropdownOpen = false
                    }
                    Task { await navigateWithHistory(path: targetPath) }
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "arrowshape.turn.up.right.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)

                        Text(dropdownDisplayName)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)

                // ".." 返回上一级
                HStack(spacing: 0) {
                    Button {
                        let parent = (dropdownBrowsingPath as NSString).deletingLastPathComponent
                        Task { await browseInDropdown(path: parent) }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)

                            Text("..")
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            // 子文件夹列表
            if isLoadingDropdown {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, AppTheme.Spacing.lg)
            } else if dropdownSubfolders.isEmpty {
                Spacer().frame(height: AppTheme.Spacing.lg)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(dropdownSubfolders) { folder in
                            HStack(spacing: 0) {
                                // 左侧主区域：点击进入浏览
                                Button {
                                    Task { await browseInDropdown(path: folder.path) }
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

                                            Text(folder.contentDescription)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                // 右侧导航按钮：点击真正导航到该文件夹
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isDropdownOpen = false
                                    }
                                    Task { await navigateWithHistory(path: folder.path) }
                                } label: {
                                    Image(systemName: "arrow.right.circle")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.vertical, AppTheme.Spacing.sm)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }

            // 底部操作按钮行：返回源文件夹 + 添加 + 排序
            HStack(spacing: AppTheme.Spacing.sm) {
                // 返回源文件夹（仅在不在根目录时显示）
                if dropdownBrowsingPath != sourceFolder && !dropdownBrowsingPath.isEmpty {
                    Button {
                        Task { await browseInDropdown(path: sourceFolder) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill.badge.gearshape")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("源文件夹")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    newFolderName = ""
                    showAddFolder = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption)
                        Text("添加")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Button {
                    showReorder = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption)
                        Text("排序")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xs)
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
                await refreshFiles()
                try? await Task.sleep(for: .milliseconds(300))
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
                        fileInfoTags = []
                        fileInfoToShow = file
                        if let uuid = file.uuid {
                            Task {
                                fileInfoTags = (try? await apiService.tag.getFileTags(fileUuid: uuid)) ?? []
                            }
                        }
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

    // MARK: - 浏览器式导航

    /// 带历史记录的导航（用户主动导航时使用）
    private func navigateWithHistory(path: String) async {
        let current = currentFolderFullPath.isEmpty ? sourceFolder : currentFolderFullPath
        if !current.isEmpty {
            historyBack.append(current)
        }
        historyForward.removeAll()
        await navigateToFolder(path: path)
    }

    /// 后退到上一个历史路径
    private func goBack() async {
        guard let prevPath = historyBack.popLast() else { return }
        let current = currentFolderFullPath.isEmpty ? sourceFolder : currentFolderFullPath
        historyForward.append(current)
        await navigateToFolder(path: prevPath)
    }

    /// 前进到下一个历史路径
    private func goForward() async {
        guard let nextPath = historyForward.popLast() else { return }
        let current = currentFolderFullPath.isEmpty ? sourceFolder : currentFolderFullPath
        historyBack.append(current)
        await navigateToFolder(path: nextPath)
    }

    /// 在下拉菜单中浏览文件夹（不触发 gallery 导航）
    private func browseInDropdown(path: String) async {
        dropdownBrowsingPath = path
        isLoadingDropdown = true
        do {
            dropdownSubfolders = try await apiService.preview.getIndexedFolders(
                parentPath: path, sourceFolder: sourceFolder)
        } catch {
            dropdownSubfolders = []
        }
        isLoadingDropdown = false
    }

    /// 在下拉菜单当前浏览路径下创建新文件夹
    private func createFolderInDropdown() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        Task {
            do {
                _ = try await apiService.folder.createFolder(name: name)
                newFolderName = ""
                // 刷新下拉菜单的子文件夹列表
                await browseInDropdown(path: dropdownBrowsingPath)
                // 同步刷新 gallery 的子文件夹（如果正在浏览同一路径）
                if dropdownBrowsingPath == currentFolderPath {
                    subfolders = dropdownSubfolders
                }
            } catch {
                GlassAlertManager.shared.showError("创建失败", message: error.localizedDescription)
            }
        }
    }

    /// 保存下拉菜单当前浏览路径的文件夹排序
    private func saveDropdownFolderOrder() {
        let order = dropdownSubfolders.map(\.name)
        Task {
            do {
                try await apiService.folder.saveFolderOrder(folderPath: dropdownBrowsingPath, order: order)
                // 同步刷新 gallery 的子文件夹（如果正在浏览同一路径）
                if dropdownBrowsingPath == currentFolderPath {
                    subfolders = dropdownSubfolders
                }
            } catch {
                GlassAlertManager.shared.showError("保存排序失败", message: error.localizedDescription)
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
            let ignoredFiles = LocalStorageService.shared.getAppSettings().ignoredFiles
            let newFiles = response.files.map { $0.toFileInfo() }
                .filter { file in !ignoredFiles.contains(file.name) }
            if reset {
                files = newFiles
            } else {
                files.append(contentsOf: newFiles)
            }
            filesOffset += response.files.count
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
        guard !isLoadingMore && !isRefreshing && hasMoreFiles else { return }
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
            let ignoredFileNames = LocalStorageService.shared.getAppSettings().ignoredFiles
            let newFiles = response.files.map { $0.toFileInfo() }
                .filter { file in !ignoredFileNames.contains(file.name) }
            files.append(contentsOf: newFiles)
            filesOffset += response.files.count
            hasMoreFiles = response.hasMore
            filesTotalCount = response.total
            return newFiles
        } catch {
            return []
        }
    }

    /// 下拉刷新 — 重置分页，从头加载当前文件夹
    private func refreshFiles() async {
        isRefreshing = true
        let path = currentFolderPath

        // 先禁止分页加载，防止哨兵触发 loadMoreFiles 导致重复 ID（不清空 files，避免闪"暂无"）
        hasMoreFiles = false

        // 并行刷新子文件夹和面包屑（各自独立处理错误）
        async let foldersTask = apiService.preview.getIndexedFolders(
            parentPath: path, sourceFolder: sourceFolder)
        async let breadcrumbTask = apiService.preview.getBreadcrumb(folderPath: path)

        do {
            let response = try await apiService.preview.getFilesPaginated(
                in: path, offset: 0, limit: filesPageSize
            )
            let ignoredFileNames = LocalStorageService.shared.getAppSettings().ignoredFiles
            let newFiles = response.files.map { $0.toFileInfo() }
                .filter { file in !ignoredFileNames.contains(file.name) }
            files = newFiles
            filesOffset = response.files.count
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

        isRefreshing = false
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
                tags: fileInfoTags,
                onAddTag: file.uuid != nil ? {
                    fileInfoToShow = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        showTagEditor = true
                    }
                } : nil,
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
        guard let file = selectedFile, let uuid = file.uuid, !renameText.isEmpty else { return }
        let newName = renameText + file.extension
        do {
            _ = try await apiService.file.renameFile(uuid: uuid, to: newName)
            GlassAlertManager.shared.showSuccess("重命名成功")
            await refreshFiles()
        } catch {
            GlassAlertManager.shared.showError("重命名失败", message: error.localizedDescription)
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

                                        Text(folder.contentDescription)
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
        guard let file, let uuid = file.uuid else { return }
        do {
            _ = try await apiService.file.moveFile(uuid: uuid, to: path)
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
        let serverId = apiService.server.id
        if let uuid {
            return apiService.preview.getThumbnailURL(
                uuid: uuid, size: size,
                baseURL: apiService.baseURL, apiKey: apiService.apiKey,
                sourceFolder: sourceFolder, serverId: serverId
            )
        }
        return apiService.preview.getThumbnailURL(
            for: path, size: size,
            baseURL: apiService.baseURL, apiKey: apiService.apiKey,
            serverId: serverId
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
