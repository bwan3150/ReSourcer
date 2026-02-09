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

    @State private var folders: [FolderInfo] = []
    @State private var selectedFolder: FolderInfo?  // nil 表示选中源文件夹
    @State private var sourceFolder = ""
    @State private var sourceFolderFileCount = 0
    @State private var files: [FileInfo] = []
    @State private var isLoading = false
    @State private var isSourceSelected = true  // 是否选中源文件夹

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
    @State private var targetFolders: [FolderInfo] = []

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
                FilePreviewView(apiService: apiService, files: files, initialIndex: index)
            }
            .navigationDestination(isPresented: $showUploadTaskList) {
                UploadTaskListView(apiService: apiService)
            }
        }
        .task {
            await loadFolders()
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
            galleryMoveSheetContent
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
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        showUploadTaskList = true
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

    private var floatingHeader: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // 文件夹选择器按钮
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDropdownOpen.toggle()
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: isSourceSelected ? "folder.fill.badge.gearshape" : "folder.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(isSourceSelected ? .orange : .yellow)

                    Text(isSourceSelected ? sourceFolderDisplayName : (selectedFolder?.name ?? "画廊"))
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: isDropdownOpen ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .glassBackground(in: Capsule())

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
            // 源文件夹选项
            Button {
                selectSourceFolder()
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "folder.fill.badge.gearshape")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(sourceFolderDisplayName)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("\(sourceFolderFileCount) 个文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSourceSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 分类文件夹列表（可滚动）
            if folders.isEmpty {
                HStack {
                    Spacer()
                    Text("暂无分类文件夹")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(folders) { folder in
                            Button {
                                selectFolder(folder)
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

                                    if !isSourceSelected && selectedFolder?.id == folder.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
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
        ScrollView {
            if viewMode == .grid {
                gridView
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

    // MARK: - Grid View

    private var gridView: some View {
        let columns = [GridItem(.adaptive(minimum: gridItemMinWidth), spacing: AppTheme.Spacing.sm)]

        return LazyVGrid(columns: columns, spacing: AppTheme.Spacing.sm) {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                NavigationLink(value: index) {
                    GalleryGridItem(file: file, apiService: apiService)
                }
                .buttonStyle(.plain)
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
                    onTap: { navPath.append(index) },
                    onInfoTap: {
                        selectedFile = file
                        fileInfoToShow = file
                    }
                )
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

    private func loadFolders() async {
        do {
            // 获取源文件夹路径
            let configState = try await apiService.config.getConfigState()
            sourceFolder = configState.sourceFolder

            // 获取分类子文件夹（已按排序返回）
            folders = try await apiService.folder.getSubfolders(in: sourceFolder)
                .filter { !$0.hidden }

            // 默认加载源文件夹
            if isSourceSelected {
                await loadFiles(path: sourceFolder)
                sourceFolderFileCount = files.count
            }
        } catch {
            if !error.isCancelledRequest {
                GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
            }
        }
    }

    private func selectSourceFolder() {
        isSourceSelected = true
        selectedFolder = nil
        files = []
        withAnimation(.easeOut(duration: 0.2)) {
            isDropdownOpen = false
        }

        Task {
            await loadFiles(path: sourceFolder)
            sourceFolderFileCount = files.count
        }
    }

    private func selectFolder(_ folder: FolderInfo) {
        isSourceSelected = false
        selectedFolder = folder
        files = []
        withAnimation(.easeOut(duration: 0.2)) {
            isDropdownOpen = false
        }

        Task {
            await loadFiles(path: sourceFolder + "/" + folder.name)
        }
    }

    private func loadFiles(path: String) async {
        isLoading = true
        GlassAlertManager.shared.showQuickLoading()
        do {
            files = try await apiService.preview.getFiles(in: path)
        } catch {
            if !error.isCancelledRequest {
                GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
            }
        }
        GlassAlertManager.shared.hideQuickLoading()
        isLoading = false
    }

    /// 下拉刷新 — 不设置 isLoading，避免触发视图重建导致 .refreshable 任务被取消
    private func refreshFiles() async {
        let path: String
        if isSourceSelected {
            path = sourceFolder
        } else if let folder = selectedFolder {
            path = sourceFolder + "/" + folder.name
        } else {
            return
        }

        do {
            // 同时刷新文件夹列表和当前文件列表
            async let newFolders = apiService.folder.getSubfolders(in: sourceFolder)
            async let newFiles = apiService.preview.getFiles(in: path)

            folders = try await newFolders.filter { !$0.hidden }
            files = try await newFiles
            if isSourceSelected {
                sourceFolderFileCount = files.count
            }
        } catch {
            if !error.isCancelledRequest {
                GlassAlertManager.shared.showError("刷新失败", message: error.localizedDescription)
            }
        }
    }

    /// 当前选中的文件夹完整路径
    private var currentFolderPath: String {
        if isSourceSelected {
            return sourceFolder
        } else if let folder = selectedFolder {
            return sourceFolder + "/" + folder.name
        }
        return sourceFolder
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
        let file = fileInfoToShow
        VStack(spacing: AppTheme.Spacing.lg) {
            galleryInfoRow("文件名", value: file?.name ?? "")
            galleryInfoRow("类型", value: file?.extension.uppercased() ?? "")
            galleryInfoRow("大小", value: file?.formattedSize ?? "")
            galleryInfoRow("修改时间", value: file?.modified ?? "")

            if let width = file?.width, let height = file?.height {
                galleryInfoRow("分辨率", value: "\(width) × \(height)")
            }
            if let duration = file?.formattedDuration {
                galleryInfoRow("时长", value: duration)
            }

            // 操作按钮
            HStack(spacing: AppTheme.Spacing.md) {
                GlassButton("重命名", icon: "pencil", style: .secondary, size: .medium) {
                    fileInfoToShow = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        renameText = selectedFile?.baseName ?? ""
                        showRenameAlert = true
                    }
                }
                .frame(maxWidth: .infinity)

                GlassButton("移动", icon: "folder", style: .secondary, size: .medium) {
                    fileInfoToShow = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        await self.loadTargetFolders()
                        showMoveSheet = true
                    }
                }
                .frame(maxWidth: .infinity)

                GlassButton("下载", icon: "arrow.down.circle", style: .secondary, size: .medium) {
                    if let file = fileInfoToShow {
                        fileInfoToShow = nil
                        saveFileToDevice(file)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, AppTheme.Spacing.sm)

            // 给底部 navbar 留空间
            Spacer().frame(height: 60)
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }

    private func galleryInfoRow(_ label: String, value: String) -> some View {
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

    @ViewBuilder
    private var galleryMoveSheetContent: some View {
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
            // 给底部 navbar 留空间
            Spacer().frame(height: 60)
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }

    // MARK: - 文件操作

    private func loadTargetFolders() async {
        do {
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

    private func performMove(to folder: FolderInfo) async {
        guard let file = selectedFile else { return }
        do {
            // 判断是否移动到源文件夹本身
            let sourceName = URL(fileURLWithPath: sourceFolder).lastPathComponent
            let targetPath = folder.name == sourceName ? sourceFolder : sourceFolder + "/" + folder.name
            _ = try await apiService.file.moveFile(at: file.path, to: targetPath)
            showMoveSheet = false
            GlassAlertManager.shared.showSuccess("已移动到 \(folder.name)")
            await refreshFiles()
        } catch {
            GlassAlertManager.shared.showError("移动失败", message: error.localizedDescription)
        }
    }
}

// MARK: - View Mode

enum GalleryViewMode {
    case grid
    case list
}

// MARK: - Gallery Grid Item

struct GalleryGridItem: View {
    let file: FileInfo
    let apiService: APIService

    var body: some View {
        // 用 Color.clear 占住正方形尺寸，图片用 overlay 填充后裁切
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                CachedThumbnailView(
                    url: apiService.preview.getThumbnailURL(
                        for: file.path,
                        size: 300,
                        baseURL: apiService.baseURL,
                        apiKey: apiService.apiKey
                    )
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.white.opacity(0.08)
                        .overlay {
                            Image(systemName: file.isVideo ? "film" : "photo")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                        }
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
}

// MARK: - Gallery List Item

struct GalleryListItem: View {
    let file: FileInfo
    let apiService: APIService
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
                        url: apiService.preview.getThumbnailURL(
                            for: file.path,
                            size: 300,
                            baseURL: apiService.baseURL,
                            apiKey: apiService.apiKey
                        )
                    ) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: file.isVideo ? "film" : "photo")
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
}

// MARK: - Preview

#Preview {
    let server = Server(name: "Test", baseURL: "http://localhost:1234", apiKey: "test")
    if let api = APIService.create(for: server) {
        GalleryView(apiService: api)
            .previewWithGlassBackground()
    }
}
