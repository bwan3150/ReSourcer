//
//  DownloadService.swift
//  ReSourcer
//
//  下载服务 - 处理 URL 检测、下载任务创建和管理
//

import Foundation

/// 下载服务
actor DownloadService {

    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    // MARK: - URL 检测

    /// 检测 URL 的平台和推荐下载器
    /// - Parameter url: 要检测的 URL
    /// - Returns: URL 检测结果
    func detectUrl(_ url: String) async throws -> UrlDetectResponse {
        let request = UrlDetectRequest(url: url)
        return try await networkManager.request(.downloadDetect, body: request)
    }

    // MARK: - 任务管理

    /// 创建下载任务
    /// - Parameters:
    ///   - url: 下载 URL
    ///   - saveFolder: 保存文件夹路径
    ///   - downloader: 指定使用的下载器（可选，默认自动检测）
    ///   - format: 下载格式（可选）
    /// - Returns: 创建的任务 ID
    func createTask(
        url: String,
        saveFolder: String,
        downloader: DownloaderType? = nil,
        format: String? = nil
    ) async throws -> String {
        let request = CreateDownloadTaskRequest(
            url: url,
            saveFolder: saveFolder,
            downloader: downloader,
            format: format
        )
        let response: CreateDownloadTaskResponse = try await networkManager.request(.downloadTask, body: request)
        return response.taskId
    }

    /// 获取所有下载任务
    /// - Returns: 下载任务列表
    func getTasks() async throws -> [DownloadTask] {
        let response: DownloadTasksResponse = try await networkManager.request(.downloadTasks)
        return response.tasks
    }

    /// 获取单个下载任务状态
    /// - Parameter taskId: 任务 ID
    /// - Returns: 下载任务信息
    func getTask(id taskId: String) async throws -> DownloadTask {
        let response: DownloadTaskStatusResponse = try await networkManager.request(.downloadTaskStatus(id: taskId))
        return response.task
    }

    /// 取消或删除下载任务
    /// - Parameter taskId: 任务 ID
    func deleteTask(id taskId: String) async throws {
        _ = try await networkManager.requestStatus(.downloadTaskDelete(id: taskId))
    }

    /// 清空下载历史记录
    func clearHistory() async throws {
        _ = try await networkManager.requestStatus(.downloadHistoryClear)
    }

    // MARK: - 便捷方法

    /// 获取活跃的下载任务
    /// - Returns: 正在进行中的下载任务列表
    func getActiveTasks() async throws -> [DownloadTask] {
        let tasks = try await getTasks()
        return tasks.filter { $0.status.isActive }
    }

    /// 获取已完成的下载任务
    /// - Returns: 已完成的下载任务列表
    func getCompletedTasks() async throws -> [DownloadTask] {
        let tasks = try await getTasks()
        return tasks.filter { $0.status == .completed }
    }

    /// 获取失败的下载任务
    /// - Returns: 失败的下载任务列表
    func getFailedTasks() async throws -> [DownloadTask] {
        let tasks = try await getTasks()
        return tasks.filter { $0.status == .failed }
    }
}
