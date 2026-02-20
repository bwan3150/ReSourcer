//
//  UploadService.swift
//  ReSourcer
//
//  上传服务 - 处理文件上传任务管理
//

import Foundation

/// 上传服务
actor UploadService {

    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    // MARK: - 任务管理

    /// 上传文件到指定文件夹
    /// - Parameters:
    ///   - files: 待上传的文件列表
    ///   - targetFolder: 目标文件夹路径
    /// - Returns: 创建的任务 ID 列表
    func uploadFiles(_ files: [PendingUploadFile], to targetFolder: String) async throws -> [String] {
        let fileData = files.map { (fileName: $0.fileName, data: $0.data, mimeType: $0.mimeType) }
        let response: CreateUploadTaskResponse = try await networkManager.upload(
            .uploadTask,
            files: fileData,
            parameters: ["target_folder": targetFolder]
        )
        return response.taskIds
    }

    /// 上传单个文件
    /// - Parameters:
    ///   - fileName: 文件名
    ///   - data: 文件数据
    ///   - mimeType: MIME 类型
    ///   - targetFolder: 目标文件夹路径
    /// - Returns: 创建的任务 ID
    func uploadFile(
        fileName: String,
        data: Data,
        mimeType: String,
        to targetFolder: String
    ) async throws -> String {
        let file = PendingUploadFile(fileName: fileName, data: data, mimeType: mimeType)
        let taskIds = try await uploadFiles([file], to: targetFolder)
        guard let taskId = taskIds.first else {
            throw APIError.unknown("上传任务创建失败")
        }
        return taskId
    }

    /// 获取所有上传任务
    /// - Returns: 上传任务列表
    func getTasks() async throws -> [UploadTask] {
        let response: UploadTasksResponse = try await networkManager.request(.uploadTasks)
        return response.tasks
    }

    /// 获取单个上传任务状态
    /// - Parameter taskId: 任务 ID
    /// - Returns: 上传任务信息
    func getTask(id taskId: String) async throws -> UploadTask {
        return try await networkManager.request(.uploadTaskStatus(id: taskId))
    }

    /// 分页获取上传历史记录
    /// - Parameters:
    ///   - offset: 偏移量
    ///   - limit: 每页数量
    ///   - status: 状态过滤（"completed" / "failed"）
    /// - Returns: 分页历史响应
    func getHistory(offset: Int, limit: Int, status: String?) async throws -> UploadHistoryResponse {
        return try await networkManager.request(.uploadHistory(offset: offset, limit: limit, status: status))
    }

    /// 删除上传任务
    /// - Parameter taskId: 任务 ID
    func deleteTask(id taskId: String) async throws {
        _ = try await networkManager.requestStatus(.uploadTaskDelete(id: taskId))
    }

    /// 清除所有已完成/失败的上传任务
    /// - Returns: 清除的任务数量
    @discardableResult
    func clearCompletedTasks() async throws -> Int {
        let response: ClearUploadTasksResponse = try await networkManager.request(.uploadTasksClear)
        return response.clearedCount
    }

    // MARK: - 便捷方法

    /// 获取活跃的上传任务
    /// - Returns: 正在进行中的上传任务列表
    func getActiveTasks() async throws -> [UploadTask] {
        let tasks = try await getTasks()
        return tasks.filter { $0.status.isActive }
    }

    /// 获取已完成的上传任务
    /// - Returns: 已完成的上传任务列表
    func getCompletedTasks() async throws -> [UploadTask] {
        let tasks = try await getTasks()
        return tasks.filter { $0.status == .completed }
    }
}
