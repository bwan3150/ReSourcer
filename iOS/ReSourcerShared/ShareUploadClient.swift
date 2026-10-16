//
//  ShareUploadClient.swift
//  ReSourcerShared
//
//  Share Extension 轻量上传客户端：复用 NetworkManager / 现有 upload·folder·sources API。
//

import Foundation
import UniformTypeIdentifiers

/// Share Extension 用的上传 / 目录客户端
actor ShareUploadClient {

    private let networkManager: NetworkManager
    private let upload: UploadService
    private let server: Server

    init(server: Server) throws {
        guard let baseURL = server.url else {
            throw APIError.invalidURL
        }
        self.server = server
        let nm = NetworkManager(baseURL: baseURL, apiKey: server.apiKey, timeoutInterval: 60)
        self.networkManager = nm
        self.upload = UploadService(networkManager: nm, apiKey: server.apiKey)
    }

    /// 源文件夹列表（当前 + 备用）
    func sourceFolders() async throws -> [String] {
        let response: SourceFoldersResponse = try await networkManager.request(.configSources)
        var paths = [response.current]
        paths.append(contentsOf: response.backups.filter { $0 != response.current })
        return paths
    }

    /// 指定源下的一级子文件夹
    func subfolders(in sourceFolder: String) async throws -> [FolderInfo] {
        try await networkManager.request(.folderList(sourceFolder: sourceFolder))
    }

    func uploadPolicyChunkSize() async throws -> Int {
        try await upload.getUploadPolicy().chunkSize
    }

    /// 小文件直传（multipart）
    @discardableResult
    func uploadDirect(fileName: String, data: Data, mimeType: String, to targetFolder: String) async throws -> String {
        try await upload.uploadFile(
            fileName: fileName,
            data: data,
            mimeType: mimeType,
            to: targetFolder
        )
    }

    /// 大文件分片（前台会话；用于 Extension 仍存活时）
    @discardableResult
    func uploadChunked(
        fileName: String,
        data: Data,
        to targetFolder: String,
        chunkSize: Int,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ChunkCompleteResponse {
        try await upload.uploadFileChunked(
            fileName: fileName,
            data: data,
            to: targetFolder,
            chunkSize: chunkSize,
            onProgress: onProgress
        )
    }

    /// 初始化分片会话（后台上传前调用）
    func initChunkedUpload(
        fileName: String,
        fileSize: UInt64,
        targetFolder: String,
        totalChunks: Int
    ) async throws -> String {
        let body = ChunkInitRequest(
            fileName: fileName,
            fileSize: fileSize,
            targetFolder: targetFolder,
            totalChunks: totalChunks
        )
        let resp: ChunkInitResponse = try await networkManager.request(.uploadChunkInit, body: body)
        return resp.uploadId
    }

    func completeChunkedUpload(uploadId: String) async throws {
        let _: ChunkCompleteResponse = try await networkManager.request(
            .uploadChunkComplete(uploadId: uploadId)
        )
    }

    func abortChunkedUpload(uploadId: String) async throws {
        try await networkManager.requestVoid(.uploadChunkAbort(uploadId: uploadId))
    }

    /// 构造分片 part 的 URLRequest（供 background URLSession 使用）
    func chunkPartRequest(uploadId: String, index: Int) throws -> URLRequest {
        try makeAuthenticatedRequest(for: .uploadChunkPart(uploadId: uploadId, index: index))
    }

    /// 构造直传 multipart 的 URLRequest（body 已写到文件）
    func directUploadRequest() throws -> URLRequest {
        var request = try makeAuthenticatedRequest(for: .uploadTask)
        // Content-Type 由调用方在写 multipart 文件时带上 boundary
        return request
    }

    private func makeAuthenticatedRequest(for endpoint: APIEndpoint) throws -> URLRequest {
        guard let url = URL(string: endpoint.path, relativeTo: server.url) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        if endpoint.requiresAuth {
            request.setValue("api_key=\(server.apiKey)", forHTTPHeaderField: "Cookie")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

// MARK: - MIME / multipart helpers

enum ShareUploadFileHelpers {
    static func mimeType(forFileName name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        if let ut = UTType(filenameExtension: ext), let mime = ut.preferredMIMEType {
            return mime
        }
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic", "heif": return "image/heic"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        default: return "application/octet-stream"
        }
    }

    /// 将 multipart body 写到 App Group 暂存文件，返回 (fileURL, contentType)
    static func writeMultipartBody(
        fileName: String,
        fileData: Data,
        mimeType: String,
        targetFolder: String,
        to directory: URL
    ) throws -> (url: URL, contentType: String) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"target_folder\"\r\n\r\n")
        body.append("\(targetFolder)\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        let out = directory.appendingPathComponent("multipart-\(UUID().uuidString).bin")
        try body.write(to: out, options: .atomic)
        return (out, "multipart/form-data; boundary=\(boundary)")
    }

    static func writeChunkFile(data: Data, index: Int, to directory: URL) throws -> URL {
        let out = directory.appendingPathComponent("chunk-\(index)-\(UUID().uuidString).bin")
        try data.write(to: out, options: .atomic)
        return out
    }
}
