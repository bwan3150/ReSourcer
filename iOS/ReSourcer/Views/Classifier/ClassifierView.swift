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

    // 文件详情弹窗
    @State private var showFileDetail = false
    @State private var renameText = ""

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

                    // 文件详情按钮（查看信息 / 重命名）
                    Button {
                        if let file = currentFile {
                            renameText = file.baseName
                            showFileDetail = true
                        }
                    } label: {
                        Image(systemName: "info.circle")
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
        .sheet(isPresented: $showFileDetail) {
            fileDetailSheet
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
            // 文件预览区域
            filePreviewSection
                .frame(maxHeight: .infinity)

            // 分类进度条
            classifyProgressBar
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.sm)

            // 可拖动的分类选择器（浮动卡片风格，与 tab bar 视觉统一）
            draggableCategorySelector
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.sm)
        }
    }

    // MARK: - File Preview Section

    @ViewBuilder
    private var filePreviewSection: some View {
        if let file = currentFile {
            // 文件预览（不含文件信息，信息移至右上角按钮）
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
            .padding(.vertical, AppTheme.Spacing.md)
        }
    }

    // MARK: - Classify Progress Bar

    private var classifyProgressBar: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
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
        .glassEffect(.regular.interactive(), in: .capsule)
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
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
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
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var fullAddButton: some View {
        Button {
            newFolderName = ""
            showAddFolder = true
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "plus.circle")
                    .font(.title3)

                Text("添加新分类")
                    .font(.body)
                    .fontWeight(.semibold)

                Spacer()
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
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
        .glassEffect(.regular.interactive(), in: .capsule)
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
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
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

    // MARK: - File Detail Sheet

    @ViewBuilder
    private var fileDetailSheet: some View {
        if let file = currentFile {
            NavigationStack {
                List {
                    // 重命名
                    Section("重命名") {
                        HStack {
                            TextField("文件名", text: $renameText)
                                .textFieldStyle(.plain)

                            Text(file.extension)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 文件信息
                    Section("文件信息") {
                        LabeledContent("类型", value: file.fileType.rawValue)
                        LabeledContent("大小", value: file.formattedSize)
                        LabeledContent("路径", value: file.path)

                        if let w = file.width, let h = file.height {
                            LabeledContent("尺寸", value: "\(w) × \(h)")
                        }
                        if let duration = file.formattedDuration {
                            LabeledContent("时长", value: duration)
                        }

                        LabeledContent("修改时间", value: file.modified)
                    }
                }
                .navigationTitle(file.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            showFileDetail = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            renameCurrentFile()
                        }
                        .disabled(renameText.isEmpty || renameText == file.baseName)
                    }
                }
            }
            .presentationDetents([.medium])
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
            classifiedCount = 0
            totalCount = files.count
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

                // 直接移动到下一个文件，不弹窗
                withAnimation(AppTheme.Animation.bouncy) {
                    classifiedCount += 1
                    currentIndex += 1
                }

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

    private func renameCurrentFile() {
        guard let file = currentFile, !renameText.isEmpty, renameText != file.baseName else { return }

        let newName = renameText + file.extension
        Task {
            do {
                let newPath = try await apiService.file.renameFile(at: file.path, to: newName)
                // 更新本地文件列表中的路径
                if let idx = files.firstIndex(where: { $0.path == file.path }) {
                    files[idx] = FileInfo(
                        name: newName,
                        path: newPath,
                        fileType: file.fileType,
                        extension: file.extension,
                        size: file.size,
                        modified: file.modified,
                        width: file.width,
                        height: file.height,
                        duration: file.duration
                    )
                }
                showFileDetail = false
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
                // 刷新分类列表
                categories = try await apiService.folder.getSubfolders(in: sourceFolder)
                    .filter { !$0.hidden }
            } catch {
                GlassAlertManager.shared.showError("创建失败", message: error.localizedDescription)
            }
        }
    }

    private func saveCategoryOrder() {
        let order = categories.map(\.name)
        Task {
            do {
                try await apiService.folder.saveCategoryOrder(sourceFolder: sourceFolder, categoryOrder: order)
            } catch {
                GlassAlertManager.shared.showError("保存排序失败", message: error.localizedDescription)
            }
        }
    }

    private func undoLastOperation() {
        guard let lastOp = operationHistory.popLast() else { return }

        Task {
            do {
                // 移回原位置
                _ = try await apiService.file.moveFile(at: lastOp.newPath, to: sourceFolder)

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
