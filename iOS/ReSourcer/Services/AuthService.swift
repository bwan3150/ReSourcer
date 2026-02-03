//
//  AuthService.swift
//  ReSourcer
//
//  认证服务 - 处理 API Key 验证和认证状态
//

import Foundation

/// 认证服务
actor AuthService {

    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    // MARK: - Public Methods

    /// 验证 API Key 是否有效
    /// - Parameter apiKey: 要验证的 API Key
    /// - Returns: 是否有效
    func verifyApiKey(_ apiKey: String) async throws -> Bool {
        let request = VerifyApiKeyRequest(apiKey: apiKey)
        let response: VerifyApiKeyResponse = try await networkManager.request(.authVerify, body: request)
        return response.valid
    }

    /// 检查当前认证状态
    /// - Returns: 当前 API Key 是否有效
    func checkAuth() async throws -> Bool {
        let response: CheckAuthResponse = try await networkManager.request(.authCheck)
        return response.valid
    }

    /// 检查服务器健康状态（不需要认证）
    /// - Returns: 健康检查响应
    func checkHealth() async throws -> HealthResponse {
        return try await networkManager.request(.health)
    }

    /// 获取 App 配置信息（不需要认证）
    /// - Returns: App 配置响应
    func getAppConfig() async throws -> AppConfigResponse {
        return try await networkManager.request(.appConfig)
    }
}
