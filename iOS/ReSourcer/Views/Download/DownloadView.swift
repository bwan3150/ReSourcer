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

    // 导航
    @State private var showTaskList = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    // 标题
                    Text("下载器")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.top, 40)

                    // 主输入区域
                    mainInputArea
                        .padding(.horizontal, AppTheme.Spacing.lg)

                    // 下载列表入口
                    Button {
                        showTaskList = true
                    } label: {
                        Text("下载列表")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, AppTheme.Spacing.md)

                    Spacer(minLength: 60)
                }
            }
            .navigationDestination(isPresented: $showTaskList) {
                DownloadTaskListView(apiService: apiService)
            }
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
                        .foregroundStyle(.primary)
                        .frame(width: 50, height: 50)
                }
                .glassEffect(.regular.interactive(), in: .circle)
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
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .glassEffect(isSelected ? .regular : .clear, in: .capsule)
    }

    private var addFolderChip: some View {
        Button {
            // TODO: 显示添加文件夹对话框
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
        .glassEffect(.clear, in: .capsule)
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
                        .tint(.primary)
                } else {
                    Image(systemName: "arrow.down")
                        .font(.title2)
                        .fontWeight(.medium)
                }
            }
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .glassEffect(isEnabled ? .regular.interactive() : .clear, in: .capsule)
        .disabled(!isEnabled || isCreatingTask)
    }

    // MARK: - Methods

    private func loadFolders() async {
        do {
            let configState = try await apiService.config.getConfigState()
            folders = try await apiService.folder.getSubfolders(in: configState.sourceFolder)
                .filter { !$0.hidden }
        } catch {
            print("加载文件夹失败: \(error)")
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
                    clearHistory()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(completedTasks.isEmpty && failedTasks.isEmpty)
            }
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
                    DownloadTaskRow(task: task) {
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
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // 平台图标
            Image(systemName: task.platform.iconName)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(statusColor.opacity(0.3)), in: .circle)

            // 任务信息
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(task.fileName ?? "下载中...")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: AppTheme.Spacing.sm) {
                    if task.status == .downloading {
                        Text(task.progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let speed = task.speed {
                            Text(speed)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                    }

                    Text(task.formattedCreatedAt)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if task.status == .downloading {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.2))

                            Capsule()
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * CGFloat(task.progress / 100))
                        }
                    }
                    .frame(height: 4)
                }
            }

            Spacer()

            // 操作按钮
            if task.status.isFinished {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else if task.canCancel {
                Button(action: onDelete) {
                    Image(systemName: "stop.circle")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
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
        case .failed: return task.error ?? "失败"
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
