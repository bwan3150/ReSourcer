//
//  GalleryView.swift
//  ReSourcer
//
//  首页 - 画廊视图
//

import SwiftUI

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
    @State private var gridColumns = 3

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // 主内容区域
                Group {
                    if isLoading && files.isEmpty {
                        loadingView
                    } else if files.isEmpty {
                        emptyView
                    } else {
                        contentView
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
            .navigationBarHidden(true)
            .navigationDestination(for: Int.self) { index in
                FilePreviewView(apiService: apiService, files: files, initialIndex: index)
            }
        }
        .task {
            await loadFolders()
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
            .glassEffect(isDropdownOpen ? .regular : .regular.interactive(), in: .capsule)

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
            .glassEffect(.regular.interactive(), in: .circle)

            // 刷新按钮
            Button {
                Task { await refreshFiles() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
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

            // 分类文件夹列表
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
        .padding(AppTheme.Spacing.sm)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
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
            await refreshFiles()
        }
    }

    // MARK: - Grid View

    private var gridView: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.sm), count: gridColumns)

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
                NavigationLink(value: index) {
                    GalleryListItem(file: file, apiService: apiService)
                }
                .buttonStyle(.plain)
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

    // MARK: - Loading View

    private var loadingView: some View {
        GlassLoadingView("加载中...")
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
            GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
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
        do {
            files = try await apiService.preview.getFiles(in: path)
        } catch {
            GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
        }
        isLoading = false
    }

    private func refreshFiles() async {
        if isSourceSelected {
            await loadFiles(path: sourceFolder)
        } else if let folder = selectedFolder {
            await loadFiles(path: sourceFolder + "/" + folder.name)
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
                AsyncImage(
                    url: apiService.preview.getThumbnailURL(
                        for: file.path,
                        size: 300,
                        baseURL: apiService.baseURL,
                        apiKey: apiService.apiKey
                    )
                ) { phase in
                    switch phase {
                    case .empty:
                        Color.white.opacity(0.08)
                            .overlay { ProgressView() }

                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)

                    case .failure:
                        Color.white.opacity(0.05)
                            .overlay {
                                Image(systemName: file.isVideo ? "film" : "photo")
                                    .font(.title2)
                                    .foregroundStyle(.tertiary)
                            }

                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // 视频时长 / GIF 标签
                if file.isVideo, let duration = file.formattedDuration {
                    Text(duration)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassEffect(.regular, in: .capsule)
                        .padding(6)
                } else if file.isGif {
                    Text("GIF")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassEffect(.regular, in: .capsule)
                        .padding(6)
                }
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

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // 缩略图
            AsyncImage(
                url: apiService.preview.getThumbnailURL(
                    for: file.path,
                    size: 150,
                    baseURL: apiService.baseURL,
                    apiKey: apiService.apiKey
                )
            ) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.sm)
                        .fill(Color.white.opacity(0.1))
                        .shimmer()

                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)

                case .failure:
                    Image(systemName: file.isVideo ? "film" : "photo")
                        .foregroundStyle(.tertiary)

                @unknown default:
                    EmptyView()
                }
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
                    // 类型标签
                    Text(file.fileType.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // 大小
                    Text(file.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // 视频时长
                    if let duration = file.formattedDuration {
                        Text(duration)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // 更多按钮
            Image(systemName: "ellipsis")
                .foregroundStyle(.tertiary)
        }
        .padding(AppTheme.Spacing.md)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
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
