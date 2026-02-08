//
//  DownloadView.swift
//  ReSourcer
//
//  下载页面 - 主界面显示输入框和下载按钮，任务列表在二级页面
//

import SwiftUI

struct DownloadView: View {

    // MARK: - Properties

    let apiService: APIService

    // 输入状态
    @State private var urlText = ""
    @State private var detectResult: UrlDetectResponse?
    @State private var isDetecting = false
    @State private var isCreatingTask = false

    // 文件夹选择
    @State private var folders: [FolderInfo] = []
    @State private var selectedFolder = ""  // 空字符串表示源文件夹

    // 新增文件夹 / 排序
    @State private var showAddFolder = false
    @State private var newFolderName = ""
    @State private var showReorder = false
    @State private var sourceFolder = ""

    // 导航
    @State private var showTaskList = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            // 整体垂直居中
            VStack(spacing: AppTheme.Spacing.xl) {
                Spacer()

                // 标题
                Text("下载器")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.primary)

                // 主输入区域
                mainInputArea
                    .padding(.horizontal, AppTheme.Spacing.lg)

                // 下载列表入口
                Button {
                    showTaskList = true
                } label: {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "list.bullet")
                            .font(.subheadline)
                        Text("下载列表")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.gray, in: .capsule)
                }

                Spacer()
            }
            .navigationDestination(isPresented: $showTaskList) {
                DownloadTaskListView(apiService: apiService)
            }
        }
        .sheet(isPresented: $showReorder) {
            NavigationStack {
                List {
                    ForEach(folders) { folder in
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
                        folders.move(fromOffsets: from, toOffset: to)
                    }
                }
                .environment(\.editMode, .constant(.active))
                .navigationTitle("调整排序")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            saveFolderOrder()
                            showReorder = false
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            showReorder = false
                            Task { await loadFolders() }
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("新建文件夹", isPresented: $showAddFolder) {
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
            await loadFolders()
        }
    }

    // MARK: - Main Input Area

    private var mainInputArea: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            // 小标题
            Text("输入链接")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            // 输入框 + 粘贴按钮
            HStack(spacing: AppTheme.Spacing.md) {
                // 输入框
                TextField("", text: $urlText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .onChange(of: urlText) { _, newValue in
                        detectURL(newValue)
                    }

                // 粘贴按钮
                Button {
                    pasteFromClipboard()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(width: 50, height: 50)
                        .background(Color.primary, in: .circle)
                }
            }

            // 文件夹选择器
            folderSelector

            // 下载按钮
            downloadButton
        }
    }

    // MARK: - Folder Selector

    private var folderSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                // 源文件夹
                folderChip(name: "", displayName: "源文件夹")

                // 其他文件夹
                ForEach(folders) { folder in
                    folderChip(name: folder.name, displayName: folder.name)
                }

                // 添加按钮
                addFolderChip

                // 排序按钮
                sortFolderChip
            }
            .padding(.vertical, 4)
        }
    }

    private func folderChip(name: String, displayName: String) -> some View {
        let isSelected = selectedFolder == name

        return Button {
            selectedFolder = name
        } label: {
            Text(displayName)
                .font(.subheadline)
                .fontWeight(isSelected ? .bold : .semibold)
                .foregroundStyle(isSelected ? Color(.systemBackground) : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? AnyShapeStyle(Color.gray) : AnyShapeStyle(.clear), in: .capsule)
        }
    }

    private var addFolderChip: some View {
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
            .padding(.vertical, 10)
        }
    }

    private var sortFolderChip: some View {
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
            .padding(.vertical, 10)
        }
    }

    // MARK: - Download Button

    private var downloadButton: some View {
        let isEnabled = !isDetecting && !urlText.trimmingCharacters(in: .whitespaces).isEmpty

        return Button {
            startDownload()
        } label: {
            Group {
                if isCreatingTask {
                    ProgressView()
                        .tint(isEnabled ? Color(.systemBackground) : .primary)
                } else {
                    Image(systemName: "arrow.down")
                        .font(.title2)
                        .fontWeight(.medium)
                }
            }
            .foregroundStyle(isEnabled ? Color(.systemBackground) : .primary.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isEnabled ? Color.primary : Color(.systemBackground), in: .capsule)
            .overlay {
                if !isEnabled {
                    Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1)
                }
            }
        }
        .disabled(!isEnabled || isCreatingTask)
    }

    // MARK: - Methods

    private func loadFolders() async {
        do {
            let configState = try await apiService.config.getConfigState()
            sourceFolder = configState.sourceFolder
            folders = try await apiService.folder.getSubfolders(in: sourceFolder)
                .filter { !$0.hidden }
        } catch {
            print("加载文件夹失败: \(error)")
        }
    }

    private func saveFolderOrder() {
        let order = folders.map(\.name)
        Task {
            do {
                try await apiService.folder.saveCategoryOrder(sourceFolder: sourceFolder, categoryOrder: order)
            } catch {
                GlassAlertManager.shared.showError("保存排序失败", message: error.localizedDescription)
            }
        }
    }

    private func detectURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            detectResult = nil
            isDetecting = false
            return
        }

        isDetecting = true

        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s 防抖

            guard urlText.trimmingCharacters(in: .whitespaces) == trimmed else { return }

            do {
                let result = try await apiService.download.detectUrl(trimmed)
                await MainActor.run {
                    detectResult = result
                    isDetecting = false
                }
            } catch {
                await MainActor.run {
                    isDetecting = false
                }
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
                await loadFolders()
            } catch {
                GlassAlertManager.shared.showError("创建失败", message: error.localizedDescription)
            }
        }
    }

    private func pasteFromClipboard() {
        if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
            urlText = text
            GlassAlertManager.shared.showSuccess("已粘贴")
        } else {
            GlassAlertManager.shared.showInfo("剪贴板为空")
        }
    }

    private func startDownload() {
        let url = urlText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }

        isCreatingTask = true

        Task {
            do {
                let config = try await apiService.config.getConfigState()
                let saveFolder = selectedFolder.isEmpty ? config.sourceFolder : "\(config.sourceFolder)/\(selectedFolder)"

                _ = try await apiService.download.createTask(url: url, saveFolder: saveFolder)

                await MainActor.run {
                    isCreatingTask = false
                    urlText = ""
                    detectResult = nil
                    showTaskList = true
                    GlassAlertManager.shared.showSuccess("已添加到下载队列")
                }
            } catch {
                await MainActor.run {
                    isCreatingTask = false
                    GlassAlertManager.shared.showError("创建失败", message: error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Download Task List View (二级页面)

struct DownloadTaskListView: View {
    let apiService: APIService

    @State private var tasks: [DownloadTask] = []
    @State private var isLoading = false
    @State private var selectedSegment: DownloadSegment = .active
    @State private var refreshTimer: Timer?
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // 分段控制器
            GlassSegmentedControl(selection: $selectedSegment, items: [
                (.active, "进行中"),
                (.completed, "已完成"),
                (.failed, "失败")
            ])
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)

            // 任务列表
            if isLoading && tasks.isEmpty {
                GlassLoadingView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredTasks.isEmpty {
                emptyView
            } else {
                taskList
            }
        }
        .navigationTitle("下载列表")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(completedTasks.isEmpty && failedTasks.isEmpty)
            }
        }
        .alert("清除记录", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { clearHistory() }
        } message: {
            Text("确定要清除所有已完成和失败的记录吗？")
        }
        .task {
            await loadTasks()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    private var filteredTasks: [DownloadTask] {
        switch selectedSegment {
        case .active: return activeTasks
        case .completed: return completedTasks
        case .failed: return failedTasks
        }
    }

    private var activeTasks: [DownloadTask] { tasks.filter { $0.status.isActive } }
    private var completedTasks: [DownloadTask] { tasks.filter { $0.status == .completed } }
    private var failedTasks: [DownloadTask] { tasks.filter { $0.status == .failed || $0.status == .cancelled } }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Spacing.sm) {
                ForEach(filteredTasks) { task in
                    DownloadTaskRow(task: task, apiService: apiService) {
                        deleteTask(task)
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .refreshable {
            await loadTasks()
        }
    }

    private var emptyView: some View {
        GlassEmptyView(
            icon: emptyIcon,
            title: emptyTitle,
            message: emptyMessage
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyIcon: String {
        switch selectedSegment {
        case .active: return "arrow.down.circle"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        }
    }

    private var emptyTitle: String {
        switch selectedSegment {
        case .active: return "没有进行中的任务"
        case .completed: return "没有已完成的任务"
        case .failed: return "没有失败的任务"
        }
    }

    private var emptyMessage: String? {
        selectedSegment == .active ? "返回上一页添加新下载" : nil
    }

    private func loadTasks() async {
        isLoading = true
        do {
            tasks = try await apiService.download.getTasks()
        } catch {
            GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
        }
        isLoading = false
    }

    private func deleteTask(_ task: DownloadTask) {
        Task {
            do {
                try await apiService.download.deleteTask(id: task.id)
                await loadTasks()
            } catch {
                GlassAlertManager.shared.showError("删除失败", message: error.localizedDescription)
            }
        }
    }

    private func clearHistory() {
        Task {
            do {
                try await apiService.download.clearHistory()
                await loadTasks()
                GlassAlertManager.shared.showSuccess("历史已清空")
            } catch {
                GlassAlertManager.shared.showError("清空失败", message: error.localizedDescription)
            }
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { await loadTasks() }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Download Segment

enum DownloadSegment: Hashable {
    case active
    case completed
    case failed
}

// MARK: - Download Task Row

struct DownloadTaskRow: View {
    let task: DownloadTask
    let apiService: APIService
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var showDeleteConfirm = false
    @State private var showFilePreview = false

    var body: some View {
        VStack(spacing: 0) {
            // 主行 — 点击展开/折叠
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    // 状态圆点
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    // 文件名
                    Text(task.fileName ?? "下载中...")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // 状态/进度
                    if task.status == .downloading {
                        Text("\(Int(task.progress))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 进度条（下载中始终显示）
            if task.status == .downloading {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.15))
                        Capsule().fill(Color.primary)
                            .frame(width: geometry.size.width * CGFloat(task.progress / 100))
                    }
                }
                .frame(height: 3)
                .padding(.top, AppTheme.Spacing.sm)
            }

            // 展开详情
            if isExpanded {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Divider().padding(.vertical, AppTheme.Spacing.xs)

                    downloadDetailRow("平台", value: task.platform.displayName)
                    downloadDetailRow("时间", value: task.formattedCreatedAt)

                    if task.status == .downloading {
                        downloadDetailRow("进度", value: task.progressText)
                        if let speed = task.speed {
                            downloadDetailRow("速度", value: speed)
                        }
                        if let eta = task.eta {
                            downloadDetailRow("剩余", value: eta)
                        }
                    }

                    // URL（可横向滚动查看）
                    HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                        Text("链接")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 32, alignment: .leading)

                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(task.url)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }

                        Button {
                            UIPasteboard.general.string = task.url
                            GlassAlertManager.shared.showSuccess("已复制")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 失败原因（可复制）
                    if task.status == .failed, let error = task.error {
                        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                            Text("原因")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: 32, alignment: .leading)

                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(3)

                            Button {
                                UIPasteboard.general.string = error
                                GlassAlertManager.shared.showSuccess("已复制")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // 操作按钮
                    HStack {
                        Spacer()
                        if task.status == .completed, task.previewFileInfo != nil {
                            Button { showFilePreview = true } label: {
                                Label("查看", systemImage: "eye")
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                        }
                        if task.status.isFinished {
                            Button { showDeleteConfirm = true } label: {
                                Label("删除", systemImage: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        } else if task.canCancel {
                            Button { showDeleteConfirm = true } label: {
                                Label("取消", systemImage: "stop.circle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(AppTheme.Spacing.md)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
        .navigationDestination(isPresented: $showFilePreview) {
            if let fileInfo = task.previewFileInfo {
                FilePreviewView(apiService: apiService, files: [fileInfo], initialIndex: 0)
            }
        }
        .alert(task.canCancel ? "取消任务" : "删除记录", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button(task.canCancel ? "确认取消" : "删除", role: .destructive) { onDelete() }
        } message: {
            Text(task.canCancel ? "确定要取消这个下载任务吗？" : "确定要删除这条记录吗？")
        }
    }

    private func downloadDetailRow(_ label: String, value: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 32, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .pending: return .gray
        case .downloading: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    private var statusText: String {
        switch task.status {
        case .pending: return "等待中"
        case .downloading: return "下载中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}

// MARK: - Preview

#Preview {
    let server = Server(name: "Test", baseURL: "http://localhost:1234", apiKey: "test")
    if let api = APIService.create(for: server) {
        DownloadView(apiService: api)
    }
}
