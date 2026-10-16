//
//  BackgroundUploadSession.swift
//  ReSourcer
//
//  后台 URLSession：App 被杀后系统继续传文件；同 identifier 恢复任务。
//  主 App 与 Share Extension 共用编译（UploadService 依赖本类型）。
//

import Foundation
import UIKit

/// 后台上传会话（单例）。所有需「杀进程后继续」的 HTTP 上传走此会话。
final class BackgroundUploadSession: NSObject, @unchecked Sendable {

    static let sessionIdentifier = "app.resourcer.apple.background-upload"
    static let shared = BackgroundUploadSession()

    /// 系统在后台事件处理完毕后调用的 completion handler
    private var backgroundCompletionHandler: (() -> Void)?

    private lazy var session: URLSession = {
        // Share Extension 编译本类型时必须带 sharedContainerIdentifier，
        // 否则系统返回 NSURLErrorBackgroundSessionRequiresSharedContainer (-995)。
        let config = Self.makeBackgroundConfiguration()
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// 供主 App / Share Extension / E2E 探针复用的后台会话配置
    static func makeBackgroundConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.sharedContainerIdentifier = AppGroup.identifier
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        // timeoutIntervalForResource 对 background 生效；给足大文件时间
        config.timeoutIntervalForResource = 60 * 60 * 6
        return config
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// taskIdentifier → 等待响应的 continuation + 累积 data
    private var pending: [Int: PendingTask] = [:]
    private let lock = NSLock()

    private struct PendingTask {
        var data = Data()
        var continuation: CheckedContinuation<Data, Error>?
        var tempFileURL: URL?
    }

    private override init() {
        super.init()
        // 触达 lazy session，尽快与系统重连已有任务
        _ = session
    }

    // MARK: - AppDelegate 钩子

    /// `application(_:handleEventsForBackgroundURLSession:completionHandler:)` 转入
    func handleEventsForBackgroundURLSession(completionHandler: @escaping () -> Void) {
        backgroundCompletionHandler = completionHandler
        // 确保 session 已创建以接收委托回调
        _ = session
    }

    // MARK: - 上传 API

    /// 将已写好的请求体文件通过 background uploadTask 发出，等待完成并返回响应 Data
    func uploadFile(
        request: URLRequest,
        fromFile fileURL: URL,
        deleteFileOnCompletion: Bool = true
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, fromFile: fileURL)
            lock.lock()
            pending[task.taskIdentifier] = PendingTask(
                continuation: continuation,
                tempFileURL: deleteFileOnCompletion ? fileURL : nil
            )
            lock.unlock()
            task.resume()
        }
    }

    /// 构造带 Cookie 认证的 URLRequest
    static func makeRequest(
        url: URL,
        method: String,
        apiKey: String,
        contentType: String?,
        requiresAuth: Bool = true
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if requiresAuth {
            request.setValue("api_key=\(apiKey)", forHTTPHeaderField: "Cookie")
        }
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: - 临时文件工具

    /// 后台上传暂存目录：优先 App Group 共享容器（Extension 与主 App 共用；配合 sharedContainerIdentifier）
    static var stagingDirectory: URL {
        let base: URL
        if let container = AppGroup.containerURL {
            base = container
        } else {
            base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        }
        let dir = base.appendingPathComponent("BackgroundUploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 把 Data 写到暂存目录，返回文件 URL
    static func writeStagingFile(data: Data, name: String) throws -> URL {
        let url = stagingDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 组装 multipart body 并写入暂存文件
    static func writeMultipartBody(
        files: [(fileName: String, data: Data, mimeType: String)],
        parameters: [String: String],
        boundary: String
    ) throws -> URL {
        var body = Data()
        for (key, value) in parameters {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        for file in files {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(file.fileName)\"\r\n")
            body.append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        let name = "multipart-\(UUID().uuidString).body"
        return try writeStagingFile(data: body, name: name)
    }
}

// MARK: - URLSessionDelegate

extension BackgroundUploadSession: URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            let handler = self?.backgroundCompletionHandler
            self?.backgroundCompletionHandler = nil
            handler?()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        pending[dataTask.taskIdentifier]?.data.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard let entry = pending.removeValue(forKey: task.taskIdentifier) else {
            lock.unlock()
            return
        }
        lock.unlock()

        if let temp = entry.tempFileURL {
            try? FileManager.default.removeItem(at: temp)
        }

        if let error {
            entry.continuation?.resume(throwing: APIError.networkError(error))
            return
        }

        guard let http = task.response as? HTTPURLResponse else {
            entry.continuation?.resume(throwing: APIError.invalidResponse)
            return
        }

        switch http.statusCode {
        case 200...299:
            entry.continuation?.resume(returning: entry.data)
        case 401:
            entry.continuation?.resume(throwing: APIError.unauthorized)
        case 404:
            entry.continuation?.resume(throwing: APIError.notFound)
        default:
            let message = (try? JSONSerialization.jsonObject(with: entry.data) as? [String: Any])
                .flatMap { $0["error"] as? String }
            entry.continuation?.resume(
                throwing: APIError.serverError(statusCode: http.statusCode, message: message)
            )
        }
    }
}

// MARK: - 可恢复分片任务持久化

/// 杀进程后可恢复的分片上传任务元数据
struct RecoverableChunkUploadJob: Codable, Identifiable, Equatable {
    let id: String
    var uploadId: String
    var fileName: String
    var fileSize: UInt64
    var targetFolder: String
    var totalChunks: Int
    var chunkSize: Int
    /// 本地源文件绝对路径（Application Support）
    var localFilePath: String
    var baseURLString: String
    var apiKey: String
    var completedIndices: [Int]
    var createdAt: Date

    var localFileURL: URL { URL(fileURLWithPath: localFilePath) }
}

/// 分片任务仓库（UserDefaults JSON）
enum ChunkUploadJobStore {
    private static let key = "background_chunk_upload_jobs"

    static func loadAll() -> [RecoverableChunkUploadJob] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RecoverableChunkUploadJob].self, from: data)) ?? []
    }

    static func saveAll(_ jobs: [RecoverableChunkUploadJob]) {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func upsert(_ job: RecoverableChunkUploadJob) {
        var all = loadAll()
        if let idx = all.firstIndex(where: { $0.id == job.id }) {
            all[idx] = job
        } else {
            all.append(job)
        }
        saveAll(all)
    }

    static func remove(id: String) {
        var all = loadAll()
        all.removeAll { $0.id == id }
        saveAll(all)
    }
}
