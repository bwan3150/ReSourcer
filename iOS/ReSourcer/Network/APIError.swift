//
//  APIError.swift
//  ReSourcer
//
//  API 错误定义
//

import Foundation

/// API 错误类型枚举
enum APIError: LocalizedError {
    /// 无效的 URL
    case invalidURL
    /// 无效的响应
    case invalidResponse
    /// 服务器错误，包含 HTTP 状态码和可选的消息
    case serverError(statusCode: Int, message: String?)
    /// JSON 解码失败
    case decodingError(Error)
    /// 网络请求失败
    case networkError(Error)
    /// 认证失败（401）
    case unauthorized
    /// 未找到资源（404）
    case notFound
    /// 请求被取消
    case cancelled
    /// 上传失败
    case uploadFailed(String)
    /// 未知错误
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .invalidResponse:
            return "服务器响应无效"
        case .serverError(let statusCode, let message):
            if let message = message {
                return "服务器错误 (\(statusCode)): \(message)"
            }
            return "服务器错误: \(statusCode)"
        case .decodingError(let error):
            return "数据解析失败: \(error.localizedDescription)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .unauthorized:
            return "认证失败，请检查 API Key"
        case .notFound:
            return "请求的资源不存在"
        case .cancelled:
            return "请求已取消"
        case .uploadFailed(let message):
            return "上传失败: \(message)"
        case .unknown(let message):
            return "未知错误: \(message)"
        }
    }
}

// MARK: - 取消判断

extension Error {
    /// 是否为请求取消错误（SwiftUI 生命周期中的正常行为，无需弹窗提示）
    var isCancelledRequest: Bool {
        if let apiError = self as? APIError, case .cancelled = apiError { return true }
        if self is CancellationError { return true }
        return false
    }
}

/// 通用 API 响应结构
struct APIResponse<T: Decodable>: Decodable {
    let status: String?
    let message: String?
    let data: T?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status, message, data, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        data = try container.decodeIfPresent(T.self, forKey: .data)
    }
}

/// 简单状态响应
struct StatusResponse: Decodable {
    let status: String?
    let message: String?
    let error: String?

    var isSuccess: Bool {
        return status == "success"
    }
}
