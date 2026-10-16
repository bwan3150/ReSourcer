//
//  UploadService.swift
//  ReSourcer
//
//  上传服务 - 处理文件上传任务管理
//  文件体上传走 background URLSession，App 被杀后系统继续传；分片状态可恢复。
//

import Foundation

/// 上传服务
actor UploadService {

    private let networkManager: NetworkManager
    private let apiKey: String

    init(networkManager: NetworkManager, apiKey: String) {
        self.networkManager = networkManager
        self.apiKey = apiKey
    }

    // MARK: - 任务管理

    /// 上传文件到指定文件夹（background URLSession）
    func uploadFiles(_ files: [PendingUploadFile], to targetFolder: String) async throws -> [String] {
        let boundary = "Boundary-\(UUID().uuidString)"
        let fileData = files.map { (fileName: $0.fileName, data: $0.data, mimeType: $0.mimeType) }
        let bodyFile = try BackgroundUploadSession.writeMultipartBody(
            files: fileData,
            parameters: ["target_folder": targetFolder],
            boundary: boundary
        )

        let baseURL = await networkManager.baseURL
        guard let url = URL(string: APIEndpoint.uploadTask.path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.invalidURL
        }
        var request = BackgroundUploadSession.makeRequest(
            url: url,
            method: "POST",
            apiKey: apiKey,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        request.timeoutInterval = 300

        let data = try await BackgroundUploadSession.shared.uploadFile(request: request, fromFile: bodyFile)
        let response: CreateUploadTaskResponse = try decode(data)
        return response.taskIds
    }

    /// 上传单个文件
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
    func getTasks() async throws -> [UploadTask] {
        let response: UploadTasksResponse = try await networkManager.request(.uploadTasks)
        return response.tasks
    }

    /// 获取单个上传任务状态
    func getTask(id taskId: String) async throws -> UploadTask {
        return try await networkManager.request(.uploadTaskStatus(id: taskId))
    }

    /// 分页获取上传历史记录
    func getHistory(offset: Int, limit: Int, status: String?) async throws -> UploadHistoryResponse {
        return try await networkManager.request(.uploadHistory(offset: offset, limit: limit, status: status))
    }

    /// 删除上传任务
    func deleteTask(id taskId: String) async throws {
        _ = try await networkManager.requestStatus(.uploadTaskDelete(id: taskId))
    }

    /// 清除所有已完成/失败的上传任务
    @discardableResult
    func clearCompletedTasks() async throws -> Int {
        let response: ClearUploadTasksResponse = try await networkManager.request(.uploadTasksClear)
        return response.clearedCount
    }

    // MARK: - 分片上传（大文件，可杀进程恢复）

    func getUploadPolicy() async throws -> UploadPolicyResponse {
        return try await networkManager.request(.uploadPolicy)
    }

    @discardableResult
    func updateUploadPolicy(chunkSizeMb: Int) async throws -> UploadPolicyResponse {
        let body = UpdateUploadPolicyRequest(chunkSizeMb: chunkSizeMb)
        return try await networkManager.request(.uploadPolicyUpdate, body: body)
    }

    /// 查询服务端已收分片（断点续传）
    func getChunkStatus(uploadId: String) async throws -> ChunkStatusResponse {
        return try await networkManager.request(.uploadChunkStatus(uploadId: uploadId))
    }

    /// 分片上传单个大文件：切分 → 逐片 background 上传 → 服务端合并。
    /// 本地源文件写入 Application Support，任务元数据持久化，App 被杀后可 `resumePendingChunkJobs` 恢复。
    @discardableResult
    func uploadFileChunked(
        fileName: String,
        data: Data,
        to targetFolder: String,
        chunkSize: Int,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ChunkCompleteResponse {
        let totalBytes = data.count
        guard chunkSize > 0 else {
            throw APIError.unknown("无效的分片大小")
        }
        let totalChunks = max(1, (totalBytes + chunkSize - 1) / chunkSize)

        // 持久化源文件，供杀进程后续传
        let jobId = UUID().uuidString
        let stagingName = "chunk-src-\(jobId)-\(fileName)"
        let localFile = try BackgroundUploadSession.writeStagingFile(data: data, name: stagingName)

        let initBody = ChunkInitRequest(
            fileName: fileName,
            fileSize: UInt64(totalBytes),
            targetFolder: targetFolder,
            totalChunks: totalChunks
        )
        let initResp: ChunkInitResponse = try await networkManager.request(.uploadChunkInit, body: initBody)
        let uploadId = initResp.uploadId

        let baseURL = await networkManager.baseURL
        var job = RecoverableChunkUploadJob(
            id: jobId,
            uploadId: uploadId,
            fileName: fileName,
            fileSize: UInt64(totalBytes),
            targetFolder: targetFolder,
            totalChunks: totalChunks,
            chunkSize: chunkSize,
            localFilePath: localFile.path,
            baseURLString: baseURL.absoluteString,
            apiKey: apiKey,
            completedIndices: [],
            createdAt: Date()
        )
        ChunkUploadJobStore.upsert(job)

        do {
            let result = try await uploadRemainingChunks(job: &job, onProgress: onProgress)
            ChunkUploadJobStore.remove(id: jobId)
            try? FileManager.default.removeItem(at: localFile)
            return result
        } catch {
            // 保留 job 以便下次 resume；失败时不立刻 abort，便于断点续传
            throw error
        }
    }

    /// App 冷启动时恢复未完成的分片任务（与 background URLSession 同 identifier 重连配合）
    @discardableResult
    func resumePendingChunkJobs(
        onProgress: (@Sendable (_ jobId: String, _ progress: Double) -> Void)? = nil
    ) async -> [String] {
        let jobs = ChunkUploadJobStore.loadAll()
        var finished: [String] = []
        for var job in jobs {
            guard FileManager.default.fileExists(atPath: job.localFilePath) else {
                ChunkUploadJobStore.remove(id: job.id)
                continue
            }
            do {
                // 与服务端对齐已收分片
                if let status = try? await getChunkStatus(uploadId: job.uploadId) {
                    job.completedIndices = status.uploaded
                    ChunkUploadJobStore.upsert(job)
                }
                let progressCb: (@Sendable (Double) -> Void)? = onProgress.map { cb in
                    { p in cb(job.id, p) }
                }
                _ = try await uploadRemainingChunks(job: &job, onProgress: progressCb)
                ChunkUploadJobStore.remove(id: job.id)
                try? FileManager.default.removeItem(at: job.localFileURL)
                finished.append(job.id)
            } catch {
                print("[Upload] 恢复分片任务失败 \(job.id): \(error.localizedDescription)")
            }
        }
        return finished
    }

    // MARK: - 便捷方法

    func getActiveTasks() async throws -> [UploadTask] {
        let tasks = try await getTasks()
        return tasks.filter { $0.status.isActive }
    }

    func getCompletedTasks() async throws -> [UploadTask] {
        let tasks = try await getTasks()
        return tasks.filter { $0.status == .completed }
    }

    // MARK: - Private

    private func uploadRemainingChunks(
        job: inout RecoverableChunkUploadJob,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> ChunkCompleteResponse {
        let fileData = try Data(contentsOf: job.localFileURL)
        let completed = Set(job.completedIndices)
        let baseURL = URL(string: job.baseURLString) ?? await networkManager.baseURL

        for index in 0..<job.totalChunks where !completed.contains(index) {
            let start = index * job.chunkSize
            let end = min(start + job.chunkSize, fileData.count)
            let chunk = fileData.subdata(in: start..<end)

            let partName = "chunk-\(job.id)-\(index).part"
            let partFile = try BackgroundUploadSession.writeStagingFile(data: chunk, name: partName)

            guard let url = URL(
                string: APIEndpoint.uploadChunkPart(uploadId: job.uploadId, index: index).path,
                relativeTo: baseURL
            )?.absoluteURL else {
                throw APIError.invalidURL
            }
            var request = BackgroundUploadSession.makeRequest(
                url: url,
                method: "POST",
                apiKey: job.apiKey,
                contentType: "application/octet-stream"
            )
            request.timeoutInterval = 300

            let respData = try await BackgroundUploadSession.shared.uploadFile(
                request: request,
                fromFile: partFile
            )
            let _: ChunkPartResponse = try decode(respData)

            job.completedIndices.append(index)
            ChunkUploadJobStore.upsert(job)
            onProgress?(Double(job.completedIndices.count) / Double(job.totalChunks))
        }

        let complete: ChunkCompleteResponse = try await networkManager.request(
            .uploadChunkComplete(uploadId: job.uploadId)
        )
        return complete
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
