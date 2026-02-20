//
//  UploadTaskListView.swift
//  ReSourcer
//
//  上传任务列表页面 — 参照 DownloadTaskListView 的模式
//

import SwiftUI

// MARK: - Upload Task List View

struct UploadTaskListView: View {
    let apiService: APIService

    // 活跃任务（轮询获取）
    @State private var activeTasks: [UploadTask] = []
    // 历史记录（分页累积）
    @State private var historyTasks: [UploadTask] = []
    @State private var historyOffset = 0
    @State private var hasMoreHistory = true
    @State private var isLoadingMore = false
    @State private var historyTotal = 0

    @State private var isLoading = false
    @State private var selectedSegment: UploadSegment = .active
    @State private var refreshTimer: Timer?
    @State private var showClearConfirm = false

    // 文件预览（从 Row 提升到此处，避免 LazyVStack 内的 navigationDestination 警告）
    @State private var showFilePreview = false
    @State private var previewFileInfo: FileInfo?

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
            .onChange(of: selectedSegment) { _, newValue in
                if newValue != .active {
                    Task { await loadHistory(reset: true) }
                }
            }

            // 任务列表
            if isLoading && filteredTasks.isEmpty {
                GlassLoadingView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredTasks.isEmpty {
                emptyView
            } else {
                taskList
            }
        }
        .navigationTitle("上传列表")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(historyTotal == 0 && selectedSegment == .active)
            }
        }
        .alert("清除记录", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { clearCompleted() }
        } message: {
            Text("确定要清除所有已完成和失败的记录吗？")
        }
        .task {
            await loadActiveTasks()
            if selectedSegment != .active {
                await loadHistory(reset: true)
            }
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    // MARK: - 过滤逻辑

    private var filteredTasks: [UploadTask] {
        switch selectedSegment {
        case .active: return activeTasks
        case .completed: return historyTasks
        case .failed: return historyTasks
        }
    }

    // MARK: - 子视图

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Spacing.sm) {
                ForEach(filteredTasks) { task in
                    UploadTaskRow(task: task, apiService: apiService, onPreview: { fileInfo in
                        previewFileInfo = fileInfo
                        showFilePreview = true
                    }) {
                        deleteTask(task)
                    }
                }

                // 底部加载触发器（仅历史 tab）
                if selectedSegment != .active && hasMoreHistory {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .onAppear { loadMoreHistory() }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .refreshable {
            if selectedSegment == .active {
                await loadActiveTasks()
            } else {
                await loadHistory(reset: true)
            }
        }
        .navigationDestination(isPresented: $showFilePreview) {
            if let fileInfo = previewFileInfo {
                FilePreviewView(apiService: apiService, files: [fileInfo], initialIndex: 0)
            }
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
        case .active: return "arrow.up.circle"
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
        selectedSegment == .active ? "返回上一页添加新上传" : nil
    }

    // MARK: - 数据加载

    /// 加载活跃任务（用于 3 秒轮询）
    private func loadActiveTasks() async {
        isLoading = true
        do {
            activeTasks = try await apiService.upload.getTasks()
        } catch {
            GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
        }
        isLoading = false
    }

    /// 加载历史记录
    /// - Parameter reset: true 时清空重新加载（切换 tab / 下拉刷新），false 时追加
    private func loadHistory(reset: Bool) async {
        if reset {
            historyOffset = 0
            historyTasks = []
            hasMoreHistory = true
        }

        let status = selectedSegment == .completed ? "completed" : "failed"

        isLoading = true
        do {
            let response = try await apiService.upload.getHistory(
                offset: historyOffset, limit: 50, status: status
            )
            if reset {
                historyTasks = response.items
            } else {
                historyTasks.append(contentsOf: response.items)
            }
            historyOffset += response.items.count
            hasMoreHistory = response.hasMore
            historyTotal = response.total
        } catch {
            GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
        }
        isLoading = false
    }

    /// 无限滚动加载更多
    private func loadMoreHistory() {
        guard !isLoadingMore && hasMoreHistory else { return }
        isLoadingMore = true
        Task {
            await loadHistory(reset: false)
            isLoadingMore = false
        }
    }

    private func deleteTask(_ task: UploadTask) {
        Task {
            do {
                try await apiService.upload.deleteTask(id: task.id)
                if selectedSegment == .active {
                    await loadActiveTasks()
                } else {
                    await loadHistory(reset: true)
                }
            } catch {
                GlassAlertManager.shared.showError("删除失败", message: error.localizedDescription)
            }
        }
    }

    private func clearCompleted() {
        Task {
            do {
                try await apiService.upload.clearCompletedTasks()
                historyTasks = []
                historyTotal = 0
                historyOffset = 0
                hasMoreHistory = true
                GlassAlertManager.shared.showSuccess("已清除")
            } catch {
                GlassAlertManager.shared.showError("清除失败", message: error.localizedDescription)
            }
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { await loadActiveTasks() }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Upload Segment

enum UploadSegment: Hashable {
    case active
    case completed
    case failed
}

// MARK: - Upload Task Row

struct UploadTaskRow: View {
    let task: UploadTask
    let apiService: APIService
    let onPreview: (FileInfo) -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var showDeleteConfirm = false

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
                    Text(task.fileName)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // 状态/进度
                    if task.status == .uploading {
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

            // 进度条（上传中始终显示）
            if task.status == .uploading {
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

                    uploadDetailRow("大小", value: task.formattedFileSize)
                    uploadDetailRow("时间", value: task.formattedCreatedAt)

                    if task.status == .uploading {
                        uploadDetailRow("进度", value: task.progressDescription)
                    }

                    uploadDetailRow("目标", value: task.targetFolder.components(separatedBy: "/").last ?? task.targetFolder)

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
                        if task.status == .completed, let fileInfo = task.previewFileInfo {
                            Button { onPreview(fileInfo) } label: {
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
        .clearGlassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
        .alert(task.canCancel ? "取消任务" : "删除记录", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button(task.canCancel ? "确认取消" : "删除", role: .destructive) { onDelete() }
        } message: {
            Text(task.canCancel ? "确定要取消这个上传任务吗？" : "确定要删除这条记录吗？")
        }
    }

    private func uploadDetailRow(_ label: String, value: String) -> some View {
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
        case .uploading: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }

    private var statusText: String {
        switch task.status {
        case .pending: return "等待中"
        case .uploading: return "上传中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}

// MARK: - Preview

#Preview {
    let server = Server(name: "Test", baseURL: "http://localhost:1234", apiKey: "test")
    if let api = APIService.create(for: server) {
        NavigationStack {
            UploadTaskListView(apiService: api)
        }
    }
}
