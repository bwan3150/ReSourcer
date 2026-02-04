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

    @State private var folders: [GalleryFolderInfo] = []
    @State private var selectedFolder: GalleryFolderInfo?
    @State private var files: [FileInfo] = []
    @State private var isLoading = false

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
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer()
                }
            }
            .navigationBarHidden(true)
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
                    Image(systemName: selectedFolder?.isSource == true ? "folder.fill.badge.gearshape" : "folder.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(selectedFolder?.isSource == true ? .orange : .yellow)

                    Text(selectedFolder?.displayName ?? "画廊")
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
        VStack(spacing: AppTheme.Spacing.sm) {
            if folders.isEmpty {
                HStack {
                    Spacer()
                    Text("暂无文件夹")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, AppTheme.Spacing.lg)
            } else {
                ForEach(folders) { folder in
                    Button {
                        selectFolder(folder)
                    } label: {
                        HStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: folder.isSource ? "folder.fill.badge.gearshape" : "folder.fill")
                                .font(.title3)
                                .foregroundStyle(folder.isSource ? .orange : .yellow)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text("\(folder.fileCount) 个文件")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if selectedFolder?.id == folder.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.sm)
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
            ForEach(files) { file in
                GalleryGridItem(file: file, apiService: apiService)
            }
        }
        .padding(AppTheme.Spacing.md)
    }

    // MARK: - List View

    private var listView: some View {
        LazyVStack(spacing: AppTheme.Spacing.sm) {
            ForEach(files) { file in
                GalleryListItem(file: file, apiService: apiService)
            }
        }
        .padding(AppTheme.Spacing.md)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        GlassEmptyView(
            icon: "photo.on.rectangle.angled",
            title: "暂无文件",
            message: selectedFolder == nil ? "请选择一个文件夹" : "该文件夹中没有媒体文件",
            actionTitle: "选择文件夹"
        ) {
            withAnimation {
                isDropdownOpen = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        GlassLoadingView("加载中...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Methods

    private func loadFolders() async {
        do {
            folders = try await apiService.folder.getGalleryFolders()

            // 如果有文件夹，自动选择第一个
            if selectedFolder == nil, let first = folders.first {
                selectFolder(first)
            }
        } catch {
            GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
        }
    }

    private func selectFolder(_ folder: GalleryFolderInfo) {
        selectedFolder = folder
        withAnimation(.easeOut(duration: 0.2)) {
            isDropdownOpen = false
        }

        Task {
            await loadFiles(in: folder)
        }
    }

    private func loadFiles(in folder: GalleryFolderInfo) async {
        isLoading = true
        do {
            files = try await apiService.preview.getFiles(in: folder.path)
        } catch {
            GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
        }
        isLoading = false
    }

    private func refreshFiles() async {
        if let folder = selectedFolder {
            await loadFiles(in: folder)
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
        ZStack(alignment: .bottomTrailing) {
            // 缩略图
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
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                        .fill(Color.white.opacity(0.1))
                        .shimmer()

                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)

                case .failure:
                    Image(systemName: file.isVideo ? "film" : "photo")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.1))

                @unknown default:
                    EmptyView()
                }
            }
            .frame(minHeight: 100)
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .cornerRadius(AppTheme.CornerRadius.md)

            // 视频时长标签
            if file.isVideo, let duration = file.formattedDuration {
                Text(duration)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .glassEffect(.regular, in: .capsule)
                    .padding(6)
            }

            // GIF 标签
            if file.isGif {
                Text("GIF")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .glassEffect(.regular.tint(.purple), in: .capsule)
                    .padding(6)
            }
        }
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
