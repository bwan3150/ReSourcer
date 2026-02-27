//
//  NetworkManager.swift
//  ReSourcer
//
//  核心网络请求管理器
//

import Foundation

/// 网络请求管理器 - 处理所有 HTTP 请求
actor NetworkManager {

    // MARK: - Properties

    /// 服务器基础 URL
    private(set) var baseURL: URL

    /// API Key 用于认证
    private let apiKey: String

    /// URLSession 配置
    private let session: URLSession

    /// JSON 解码器
    private let decoder: JSONDecoder

    /// JSON 编码器
    private let encoder: JSONEncoder

    // MARK: - Initialization

    /// 初始化网络管理器
    /// - Parameters:
    ///   - baseURL: 服务器基础 URL
    ///   - apiKey: API Key 用于认证
    ///   - timeoutInterval: 请求超时时间（默认 30 秒）
    init(baseURL: URL, apiKey: String, timeoutInterval: TimeInterval = 30) {
        self.baseURL = baseURL
        self.apiKey = apiKey

        // 配置 URLSession
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutInterval
        configuration.timeoutIntervalForResource = timeoutInterval * 2
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: configuration)

        // 配置 JSON 解码器
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601

        // 配置 JSON 编码器
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    /// 切换 baseURL（用于多地址切换）
    func updateBaseURL(_ newURL: URL) {
        self.baseURL = newURL
    }

    // MARK: - Public Methods

    /// 执行 API 请求并返回解码后的响应
    /// - Parameters:
    ///   - endpoint: API 端点
    ///   - body: 请求体（可选）
    /// - Returns: 解码后的响应数据
    func request<T: Decodable>(_ endpoint: APIEndpoint, body: Encodable? = nil) async throws -> T {
        let request = try buildRequest(for: endpoint, body: body)
        let (data, response) = try await performRequest(request)
        return try decodeResponse(data, response: response)
    }

    /// 执行 API 请求，不期望返回数据（仅状态）
    /// - Parameters:
    ///   - endpoint: API 端点
    ///   - body: 请求体（可选）
    func requestVoid(_ endpoint: APIEndpoint, body: Encodable? = nil) async throws {
        let request = try buildRequest(for: endpoint, body: body)
        let (_, response) = try await performRequest(request)
        try validateResponse(response)
    }

    /// 执行 API 请求并返回状态响应
    /// - Parameters:
    ///   - endpoint: API 端点
    ///   - body: 请求体（可选）
    /// - Returns: 状态响应
    func requestStatus(_ endpoint: APIEndpoint, body: Encodable? = nil) async throws -> StatusResponse {
        return try await request(endpoint, body: body)
    }

    /// 下载文件数据（用于预览、缩略图等）
    /// - Parameter endpoint: API 端点
    /// - Returns: 原始数据
    func downloadData(_ endpoint: APIEndpoint) async throws -> Data {
        let request = try buildRequest(for: endpoint, body: nil as EmptyBody?)
        let (data, response) = try await performRequest(request)
        try validateResponse(response)
        return data
    }

    /// 上传文件（multipart/form-data）
    /// - Parameters:
    ///   - endpoint: API 端点
    ///   - files: 要上传的文件数组 (fileName, data, mimeType)
    ///   - parameters: 额外的表单参数
    /// - Returns: 解码后的响应
    func upload<T: Decodable>(
        _ endpoint: APIEndpoint,
        files: [(fileName: String, data: Data, mimeType: String)],
        parameters: [String: String] = [:]
    ) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try buildRequest(for: endpoint, body: nil as EmptyBody?)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // 添加表单参数
        for (key, value) in parameters {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        // 添加文件
        for file in files {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(file.fileName)\"\r\n")
            body.append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")
        request.httpBody = body
        // 上传大文件需要更长的超时时间（5 分钟）
        request.timeoutInterval = 300

        let (data, response) = try await performRequest(request)
        return try decodeResponse(data, response: response)
    }

    /// 上传原始文本内容（用于 credentials 等）
    /// - Parameters:
    ///   - endpoint: API 端点
    ///   - content: 文本内容
    /// - Returns: 状态响应
    func uploadText(_ endpoint: APIEndpoint, content: String) async throws -> StatusResponse {
        var request = try buildRequest(for: endpoint, body: nil as EmptyBody?)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = content.data(using: .utf8)

        let (data, response) = try await performRequest(request)
        return try decodeResponse(data, response: response)
    }

    // MARK: - Private Methods

    /// 构建 URLRequest
    private func buildRequest(for endpoint: APIEndpoint, body: Encodable?) throws -> URLRequest {
        guard let url = URL(string: endpoint.path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue

        // 设置认证 Cookie
        if endpoint.requiresAuth {
            request.setValue("api_key=\(apiKey)", forHTTPHeaderField: "Cookie")
        }

        // 设置请求体
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return request
    }

    /// 执行网络请求
    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled {
                throw APIError.cancelled
            }
            throw APIError.networkError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }

    /// 验证响应状态码
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: nil)
        }
    }

    /// 解码响应数据
    private func decodeResponse<T: Decodable>(_ data: Data, response: URLResponse) throws -> T {
        try validateResponse(response)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

// MARK: - Helper Types

/// 空请求体
private struct EmptyBody: Encodable {}

/// 类型擦除的 Encodable 包装器
private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encode = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}

// MARK: - Data Extension

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
