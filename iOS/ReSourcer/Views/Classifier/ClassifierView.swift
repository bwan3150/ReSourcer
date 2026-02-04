//
//  ClassifierView.swift
//  ReSourcer
//
//  分类页面 - 快速分类文件到不同文件夹
//

import SwiftUI

struct ClassifierView: View {

    // MARK: - Properties

    let apiService: APIService

    @State private var files: [FileInfo] = []
    @State private var categories: [FolderInfo] = []
    @State private var currentIndex = 0
    @State private var sourceFolder: String = ""
    @State private var isLoading = false
    @State private var showSettings = false

    // 操作历史（用于撤销）
    @State private var operationHistory: [ClassifyOperation] = []

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
            .navigationTitle("分类")
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

                    // 刷新
                    Button {
                        Task { await loadData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
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

    // MARK: - Classifier Content

    private var classifierContent: some View {
        VStack(spacing: 0) {
            // 文件预览区域
            filePreviewSection
                .frame(maxHeight: .infinity)

            // 分类按钮区域
            categoryButtonsSection
        }
    }

    // MARK: - File Preview Section

    @ViewBuilder
    private var filePreviewSection: some View {
        if let file = currentFile {
            VStack(spacing: AppTheme.Spacing.md) {
                // 文件预览
                AsyncImage(
                    url: apiService.preview.getThumbnailURL(
                        for: file.path,
                        size: 600,
                        baseURL: apiService.baseURL,
                        apiKey: apiService.apiKey
                    )
                ) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg)
                            .fill(Color.white.opacity(0.1))
                            .shimmer()

                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(AppTheme.CornerRadius.lg)

                    case .failure:
                        VStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: file.isVideo ? "film" : "photo")
                                .font(.system(size: 48))
                                .foregroundStyle(.tertiary)

                            Text("无法加载预览")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, AppTheme.Spacing.lg)

                // 文件信息
                VStack(spacing: AppTheme.Spacing.xxs) {
                    Text(file.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    HStack(spacing: AppTheme.Spacing.md) {
                        Label(file.fileType.rawValue, systemImage: file.isVideo ? "film" : "photo")
                        Label(file.formattedSize, systemImage: "doc")
                        if let duration = file.formattedDuration {
                            Label(duration, systemImage: "clock")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
            }
            .padding(.vertical, AppTheme.Spacing.md)
        }
    }

    // MARK: - Category Buttons Section

    private var categoryButtonsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(categories) { category in
                    categoryButton(for: category)
                }

                // 新建分类按钮
                GlassButton(icon: "plus", style: .secondary, size: .medium) {
                    // TODO: 显示新建分类弹窗
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
        }
        .glassEffect(.regular, in: UnevenRoundedRectangle(
            topLeadingRadius: AppTheme.CornerRadius.xl,
            topTrailingRadius: AppTheme.CornerRadius.xl
        ))
    }

    @ViewBuilder
    private func categoryButton(for category: FolderInfo) -> some View {
        GlassButton(
            category.name,
            icon: "folder.fill",
            style: .primary,
            size: .medium
        ) {
            classifyToCategory(category)
        }
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

    // MARK: - Methods

    private func loadData() async {
        isLoading = true

        do {
            // 获取配置状态
            let configState = try await apiService.config.getConfigState()
            sourceFolder = configState.sourceFolder

            // 获取待分类文件
            files = try await apiService.file.getFiles(in: sourceFolder)

            // 获取分类文件夹
            categories = try await apiService.folder.getSubfolders(in: sourceFolder)
                .filter { !$0.hidden }

            currentIndex = 0
            operationHistory = []

        } catch {
            GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
        }

        isLoading = false
    }

    private func classifyToCategory(_ category: FolderInfo) {
        guard let file = currentFile else { return }

        Task {
            do {
                let targetPath = "\(sourceFolder)/\(category.name)"
                let newPath = try await apiService.file.moveFile(at: file.path, to: targetPath)

                // 记录操作历史
                let operation = ClassifyOperation(
                    file: file,
                    fromIndex: currentIndex,
                    toCategory: category.name,
                    newPath: newPath
                )
                operationHistory.append(operation)

                // 移动到下一个文件
                withAnimation(AppTheme.Animation.bouncy) {
                    currentIndex += 1
                }

                // 提示成功
                GlassAlertManager.shared.showSuccess("已分类到 \(category.name)")

            } catch {
                GlassAlertManager.shared.showError("分类失败", message: error.localizedDescription)
            }
        }
    }

    private func skipCurrentFile() {
        guard currentFile != nil else { return }

        withAnimation(AppTheme.Animation.bouncy) {
            currentIndex += 1
        }
    }

    private func undoLastOperation() {
        guard let lastOp = operationHistory.popLast() else { return }

        Task {
            do {
                // 移回原位置
                _ = try await apiService.file.moveFile(at: lastOp.newPath, to: sourceFolder)

                // 恢复索引
                withAnimation(AppTheme.Animation.bouncy) {
                    currentIndex = lastOp.fromIndex
                }

                GlassAlertManager.shared.showInfo("已撤销")

            } catch {
                GlassAlertManager.shared.showError("撤销失败", message: error.localizedDescription)
                // 恢复操作历史
                operationHistory.append(lastOp)
            }
        }
    }
}

// MARK: - Classify Operation

/// 分类操作记录（用于撤销）
struct ClassifyOperation {
    let file: FileInfo
    let fromIndex: Int
    let toCategory: String
    let newPath: String
}

// MARK: - Preview

#Preview {
    let server = Server(name: "Test", baseURL: "http://localhost:1234", apiKey: "test")
    if let api = APIService.create(for: server) {
        ClassifierView(apiService: api)
            .previewWithGlassBackground()
    }
}
