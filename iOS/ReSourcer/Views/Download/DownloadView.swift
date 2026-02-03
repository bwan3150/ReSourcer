//
//  DownloadView.swift
//  ReSourcer
//
//  下载页面 - 管理下载任务
//

import SwiftUI

struct DownloadView: View {

    // MARK: - Properties

    let apiService: APIService

    @State private var tasks: [DownloadTask] = []
    @State private var isLoading = false
    @State private var showAddTask = false
    @State private var selectedSegment: DownloadSegment = .active

    // 新建任务表单
    @State private var newTaskURL = ""
    @State private var detectResult: UrlDetectResponse?
    @State private var isDetecting = false
    @State private var isCreatingTask = false

    // 自动刷新
    @State private var refreshTimer: Timer?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            navigationBar

            // 分段控制器
            segmentControl
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)

            // 任务列表
            if isLoading && tasks.isEmpty {
                loadingView
            } else if filteredTasks.isEmpty {
                emptyView
            } else {
                taskList
            }
        }
        .task {
            await loadTasks()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .glassBottomSheet(
            isPresented: $showAddTask,
            title: "新建下载"
        ) {
            addTaskContent
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        GlassNavigationBar(
            title: "下载",
            subtitle: activeTasks.isEmpty ? nil : "\(activeTasks.count) 个任务进行中",
            leading: {
                // 清空历史
                GlassNavBarButton("trash") {
                    clearHistory()
                }
                .opacity(completedTasks.isEmpty ? 0.3 : 1)
            },
            trailing: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    // 刷新
                    GlassNavBarButton("arrow.clockwise") {
                        Task { await loadTasks() }
                    }

                    // 添加任务
                    GlassNavBarButton("plus") {
                        showAddTask = true
                    }
                }
            }
        )
    }

    // MARK: - Segment Control

    private var segmentControl: some View {
        GlassSegmentedControl(selection: $selectedSegment, items: [
            (.active, "进行中"),
            (.completed, "已完成"),
            (.failed, "失败")
        ])
    }

    // MARK: - Filtered Tasks

    private var filteredTasks: [DownloadTask] {
        switch selectedSegment {
        case .active:
            return activeTasks
        case .completed:
            return completedTasks
        case .failed:
            return failedTasks
        }
    }

    private var activeTasks: [DownloadTask] {
        tasks.filter { $0.status.isActive }
    }

    private var completedTasks: [DownloadTask] {
        tasks.filter { $0.status == .completed }
    }

    private var failedTasks: [DownloadTask] {
        tasks.filter { $0.status == .failed || $0.status == .cancelled }
    }

    // MARK: - Task List

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

    // MARK: - Empty View

    private var emptyView: some View {
        GlassEmptyView(
            icon: emptyIcon,
            title: emptyTitle,
            message: emptyMessage,
            actionTitle: selectedSegment == .active ? "添加下载" : nil
        ) {
            showAddTask = true
        }
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
        switch selectedSegment {
        case .active: return "点击右上角 + 添加新下载"
        case .completed: return nil
        case .failed: return nil
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        GlassLoadingView("加载中...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Add Task Content

    private var addTaskContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // URL 输入
            GlassTextField(
                "下载链接",
                text: $newTaskURL,
                placeholder: "粘贴视频/图片链接",
                icon: "link"
            )
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .onChange(of: newTaskURL) { _, newValue in
                if !newValue.isEmpty {
                    detectURL(newValue)
                } else {
                    detectResult = nil
                }
            }

            // 检测结果
            if isDetecting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在检测...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else if let result = detectResult {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: result.platform.iconName)
                        .font(.title2)
                        .foregroundStyle(platformColor(result.platform))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.platformName)
                            .font(.subheadline)
                            .foregroundStyle(.white)

                        Text("使用 \(result.downloader.displayName) 下载")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()

                    if result.requiresAuth {
                        Label("需要登录", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(AppTheme.Spacing.md)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
            }

            // 创建按钮
            GlassButton.primary(
                "开始下载",
                icon: "arrow.down.circle",
                size: .large,
                isLoading: isCreatingTask
            ) {
                createTask()
            }
            .disabled(newTaskURL.isEmpty || detectResult == nil)
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }

    private func platformColor(_ platform: Platform) -> Color {
        switch platform {
        case .youtube: return .red
        case .bilibili: return .pink
        case .x: return .blue
        case .tiktok: return .cyan
        case .pixiv: return .blue
        case .xiaohongshu: return .red
        case .unknown: return .gray
        }
    }

    // MARK: - Methods

    private func loadTasks() async {
        isLoading = true
        do {
            tasks = try await apiService.download.getTasks()
        } catch {
            GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
        }
        isLoading = false
    }

    private func detectURL(_ url: String) {
        // 防抖
        isDetecting = true
        detectResult = nil

        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

            guard newTaskURL == url else { return } // URL 已变化

            do {
                let result = try await apiService.download.detectUrl(url)
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

    private func createTask() {
        guard !newTaskURL.isEmpty else { return }

        isCreatingTask = true

        Task {
            do {
                // 获取保存路径（使用配置的源文件夹）
                let config = try await apiService.config.getConfigState()

                _ = try await apiService.download.createTask(
                    url: newTaskURL,
                    saveFolder: config.sourceFolder
                )

                await MainActor.run {
                    isCreatingTask = false
                    showAddTask = false
                    newTaskURL = ""
                    detectResult = nil
                    GlassAlertManager.shared.showSuccess("已添加到下载队列")
                }

                // 刷新任务列表
                await loadTasks()

            } catch {
                await MainActor.run {
                    isCreatingTask = false
                    GlassAlertManager.shared.showError("创建失败", message: error.localizedDescription)
                }
            }
        }
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
            Task {
                await loadTasks()
            }
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
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: AppTheme.Spacing.sm) {
                    // 状态/进度
                    if task.status == .downloading {
                        Text("\(task.progressText)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))

                        if let speed = task.speed {
                            Text(speed)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    } else {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                    }

                    Text(task.formattedCreatedAt)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                // 进度条
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
                        .foregroundStyle(.white.opacity(0.5))
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
            .previewWithGlassBackground()
    }
}
