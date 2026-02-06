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

    @State private var tasks: [UploadTask] = []
    @State private var isLoading = false
    @State private var selectedSegment: UploadSegment = .active
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
        .navigationTitle("上传列表")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    clearCompleted()
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

    // MARK: - 过滤逻辑

    private var filteredTasks: [UploadTask] {
        switch selectedSegment {
        case .active: return activeTasks
        case .completed: return completedTasks
        case .failed: return failedTasks
        }
    }

    private var activeTasks: [UploadTask] { tasks.filter { $0.status.isActive } }
    private var completedTasks: [UploadTask] { tasks.filter { $0.status == .completed } }
    private var failedTasks: [UploadTask] { tasks.filter { $0.status == .failed } }

    // MARK: - 子视图

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Spacing.sm) {
                ForEach(filteredTasks) { task in
                    UploadTaskRow(task: task) {
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

    // MARK: - 方法

    private func loadTasks() async {
        isLoading = true
        do {
            tasks = try await apiService.upload.getTasks()
        } catch {
            GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
        }
        isLoading = false
    }

    private func deleteTask(_ task: UploadTask) {
        Task {
            do {
                try await apiService.upload.deleteTask(id: task.id)
                await loadTasks()
            } catch {
                GlassAlertManager.shared.showError("删除失败", message: error.localizedDescription)
            }
        }
    }

    private func clearCompleted() {
        Task {
            do {
                try await apiService.upload.clearCompletedTasks()
                await loadTasks()
                GlassAlertManager.shared.showSuccess("已清除")
            } catch {
                GlassAlertManager.shared.showError("清除失败", message: error.localizedDescription)
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

// MARK: - Upload Segment

enum UploadSegment: Hashable {
    case active
    case completed
    case failed
}

// MARK: - Upload Task Row

struct UploadTaskRow: View {
    let task: UploadTask
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // 图标
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(statusColor.opacity(0.3)), in: .circle)

            // 任务信息
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(task.fileName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: AppTheme.Spacing.sm) {
                    if task.status == .uploading {
                        Text(task.progressDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                    }

                    Text(task.formattedFileSize)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // 进度条
                if task.status == .uploading {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.2))

                            Capsule()
                                .fill(Color.primary)
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
        case .failed: return task.error ?? "失败"
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
