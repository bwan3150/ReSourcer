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
    @State private var showFolderPicker = false

    // 显示模式
    @State private var viewMode: GalleryViewMode = .grid
    @State private var gridColumns = 3

    // MARK: - Body

    var body: some View {
        // 使用 NavigationStack，iOS 26 自动应用 Liquid Glass
        NavigationStack {
            Group {
                // 内容区域
                if isLoading && files.isEmpty {
                    loadingView
                } else if files.isEmpty {
                    emptyView
                } else {
                    contentView
                }
            }
            .navigationTitle(selectedFolder?.displayName ?? "画廊")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFolderPicker = true
                    } label: {
                        Image(systemName: "folder")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    // 视图模式切换
                    Button {
                        withAnimation {
                            viewMode = viewMode == .grid ? .list : .grid
                        }
                    } label: {
                        Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                    }

                    // 刷新
                    Button {
                        Task {
                            await refreshFiles()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            await loadFolders()
        }
        .glassBottomSheet(
            isPresented: $showFolderPicker,
            title: "选择文件夹"
        ) {
            folderPickerContent
        }
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
            showFolderPicker = true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        GlassLoadingView("加载中...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Folder Picker

    private var folderPickerContent: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if folders.isEmpty {
                GlassEmptyView(
                    icon: "folder",
                    title: "暂无文件夹",
                    message: "请在服务器上配置源文件夹"
                )
            } else {
                ForEach(folders) { folder in
                    Button {
                        selectFolder(folder)
                    } label: {
                        HStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: folder.isSource ? "folder.fill.badge.gearshape" : "folder.fill")
                                .font(.title2)
                                .foregroundStyle(folder.isSource ? .orange : .yellow)

                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                                Text(folder.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)

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
                        .padding(AppTheme.Spacing.md)
                        .glassEffect(
                            selectedFolder?.id == folder.id ? .regular : .clear,
                            in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
        showFolderPicker = false

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
