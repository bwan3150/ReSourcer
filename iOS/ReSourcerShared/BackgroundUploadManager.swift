//
//  BackgroundUploadManager.swift
//  ReSourcerShared
//
//  Share Extension 大文件后台上传（background URLSession）。
//  关掉 Extension UI 后系统仍可继续传；完成事件由主 App / Extension 共用会话处理。
//

import Foundation

/// 后台上传管理器（主 App 与 Share Extension 共用同一 session identifier）
final class BackgroundUploadManager: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {

    static let shared = BackgroundUploadManager()

    private var session: URLSession!
    private var completionHandlers: [String: () -> Void] = [:]
    private let lock = NSLock()

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: AppGroup.backgroundUploadSessionId)
        config.sharedContainerIdentifier = AppGroup.identifier
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// 主 App 收到系统唤醒时挂上 completion handler
    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void, for identifier: String) {
        lock.lock()
        completionHandlers[identifier] = handler
        lock.unlock()
    }

    /// 直传：multipart 已写入 fileURL
    @discardableResult
    func enqueueDirectUpload(
        request: URLRequest,
        bodyFileURL: URL,
        job: ShareBridge.BackgroundUploadJob
    ) -> URLSessionUploadTask {
        ShareBridge.upsertBackgroundJob(job)
        var req = request
        req.httpMethod = "POST"
        let task = session.uploadTask(with: req, fromFile: bodyFileURL)
        task.taskDescription = job.id
        task.resume()
        return task
    }

    /// 分片 part 上传
    @discardableResult
    func enqueueChunkPart(
        request: URLRequest,
        chunkFileURL: URL,
        jobId: String,
        chunkIndex: Int
    ) -> URLSessionUploadTask {
        var req = request
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let task = session.uploadTask(with: req, fromFile: chunkFileURL)
        task.taskDescription = "\(jobId)#\(chunkIndex)"
        task.resume()
        return task
    }

    // MARK: - URLSessionDelegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let description = task.taskDescription else { return }

        if description.contains("#") {
            let parts = description.split(separator: "#", maxSplits: 1).map(String.init)
            guard parts.count == 2, let index = Int(parts[1]) else { return }
            let jobId = parts[0]
            handleChunkCompletion(jobId: jobId, index: index, error: error, task: task)
            return
        }

        handleDirectCompletion(jobId: description, error: error, task: task)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let id = session.configuration.identifier ?? AppGroup.backgroundUploadSessionId
        lock.lock()
        let handler = completionHandlers.removeValue(forKey: id)
        lock.unlock()
        DispatchQueue.main.async {
            handler?()
        }
    }

    // MARK: - Completion helpers

    private func handleDirectCompletion(jobId: String, error: Error?, task: URLSessionTask) {
        defer { ShareBridge.removeBackgroundJob(id: jobId) }
        if let error {
            print("[ShareUpload] direct failed \(jobId): \(error)")
            return
        }
        if let http = task.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            print("[ShareUpload] direct HTTP \(http.statusCode) for \(jobId)")
            return
        }
        if let job = ShareBridge.loadBackgroundJobs().first(where: { $0.id == jobId }) {
            try? FileManager.default.removeItem(atPath: job.localFilePath)
        }
    }

    private func handleChunkCompletion(jobId: String, index: Int, error: Error?, task: URLSessionTask) {
        var jobs = ShareBridge.loadBackgroundJobs()
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        if let error {
            print("[ShareUpload] chunk \(index) failed \(jobId): \(error)")
            return
        }
        if let http = task.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            print("[ShareUpload] chunk \(index) HTTP \(http.statusCode) for \(jobId)")
            return
        }

        if !jobs[idx].completedChunkIndexes.contains(index) {
            jobs[idx].completedChunkIndexes.append(index)
        }
        ShareBridge.saveBackgroundJobs(jobs)

        let job = jobs[idx]
        guard let total = job.totalChunks, let uploadId = job.uploadId else { return }
        let done = Set(job.completedChunkIndexes)
        guard done.count >= total, (0..<total).allSatisfy({ done.contains($0) }) else { return }

        // 全部分片完成 → 调 complete（前台短请求）
        Task {
            await finalizeChunkedJob(job)
        }
    }

    private func finalizeChunkedJob(_ job: ShareBridge.BackgroundUploadJob) async {
        guard let uploadId = job.uploadId else { return }
        guard let server = ShareBridge.loadServers().first(where: { $0.id == job.serverId })
                ?? ShareBridge.loadServers().first(where: { $0.baseURL == job.baseURL }) else {
            return
        }
        do {
            let client = try ShareUploadClient(server: server)
            try await client.completeChunkedUpload(uploadId: uploadId)
            ShareBridge.removeBackgroundJob(id: job.id)
            try? FileManager.default.removeItem(atPath: job.localFilePath)
            // 清理分片临时文件目录旁的 chunk-*
            if let staging = AppGroup.uploadStagingURL {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: staging, includingPropertiesForKeys: nil
                )) ?? []
                for url in contents where url.lastPathComponent.hasPrefix("chunk-") {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        } catch {
            print("[ShareUpload] complete failed \(job.id): \(error)")
        }
    }

    /// 主 App 启动时尝试收尾未完成的分片任务
    func resumePendingFinalizations() {
        let jobs = ShareBridge.loadBackgroundJobs()
        for job in jobs {
            guard job.kind == .chunked,
                  let total = job.totalChunks,
                  Set(job.completedChunkIndexes).count >= total else { continue }
            Task { await finalizeChunkedJob(job) }
        }
    }
}
