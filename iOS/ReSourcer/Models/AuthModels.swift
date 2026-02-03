//
//  AuthModels.swift
//  ReSourcer
//
//  认证相关数据模型
//

import Foundation

/// 验证 API Key 请求
struct VerifyApiKeyRequest: Codable {
    let apiKey: String
}

/// 验证 API Key 响应
struct VerifyApiKeyResponse: Codable {
    let valid: Bool
}

/// 检查认证状态响应
struct CheckAuthResponse: Codable {
    let valid: Bool
}

// MARK: - 平台认证

/// 支持的认证平台
enum AuthPlatform: String, CaseIterable {
    case x = "x"           // X (Twitter)
    case pixiv = "pixiv"   // Pixiv

    /// 平台显示名称
    var displayName: String {
        switch self {
        case .x: return "X (Twitter)"
        case .pixiv: return "Pixiv"
        }
    }

    /// 认证类型描述
    var authTypeDescription: String {
        switch self {
        case .x: return "Cookies"
        case .pixiv: return "Token"
        }
    }

    /// 认证说明
    var instructions: String {
        switch self {
        case .x:
            return """
            请提供 X (Twitter) 的 cookies 文件内容。
            可以使用浏览器扩展导出 Netscape 格式的 cookies。
            """
        case .pixiv:
            return """
            请提供 Pixiv 的 refresh token。
            可以从 Pixiv Toolkit 或其他工具获取。
            """
        }
    }
}

/// 平台认证信息
struct PlatformCredential: Identifiable {
    let platform: AuthPlatform
    let isConfigured: Bool

    var id: String { platform.rawValue }
}
