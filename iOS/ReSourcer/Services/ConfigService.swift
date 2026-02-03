//
//  ConfigService.swift
//  ReSourcer
//
//  配置服务 - 处理全局配置、源文件夹、认证和预设管理
//

import Foundation

/// 配置服务
actor ConfigService {

    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    // MARK: - 全局配置

    /// 获取全局配置
    /// - Returns: 全局配置响应
    func getGlobalConfig() async throws -> GlobalConfigResponse {
        return try await networkManager.request(.config)
    }

    /// 获取配置状态（包含预设信息）
    /// - Returns: 配置状态响应
    func getConfigState() async throws -> ConfigStateResponse {
        return try await networkManager.request(.configState)
    }

    /// 保存配置
    /// - Parameters:
    ///   - sourceFolder: 源文件夹路径
    ///   - categories: 分类名称列表
    ///   - hiddenFolders: 隐藏文件夹列表
    func saveConfig(sourceFolder: String, categories: [String], hiddenFolders: [String]) async throws {
        let request = SaveConfigRequest(
            sourceFolder: sourceFolder,
            categories: categories,
            hiddenFolders: hiddenFolders
        )
        _ = try await networkManager.requestStatus(.configSave, body: request)
    }

    // MARK: - 下载器配置

    /// 获取下载器配置和认证状态
    /// - Returns: 下载器配置响应
    func getDownloadConfig() async throws -> DownloadConfigResponse {
        return try await networkManager.request(.configDownload)
    }

    /// 保存下载器配置
    /// - Parameters:
    ///   - sourceFolder: 源文件夹路径
    ///   - hiddenFolders: 隐藏文件夹列表
    ///   - useCookies: 是否使用 cookies
    func saveDownloadConfig(sourceFolder: String, hiddenFolders: [String], useCookies: Bool) async throws {
        let request = SaveDownloadConfigRequest(
            sourceFolder: sourceFolder,
            hiddenFolders: hiddenFolders,
            useCookies: useCookies
        )
        _ = try await networkManager.requestStatus(.configDownloadSave, body: request)
    }

    // MARK: - 源文件夹管理

    /// 获取所有源文件夹列表
    /// - Returns: 源文件夹响应
    func getSourceFolders() async throws -> SourceFoldersResponse {
        return try await networkManager.request(.configSources)
    }

    /// 添加备用源文件夹
    /// - Parameter folderPath: 文件夹路径
    func addSourceFolder(_ folderPath: String) async throws {
        let request = SourceFolderRequest(folderPath: folderPath)
        _ = try await networkManager.requestStatus(.configSourcesAdd, body: request)
    }

    /// 移除备用源文件夹
    /// - Parameter folderPath: 文件夹路径
    func removeSourceFolder(_ folderPath: String) async throws {
        let request = SourceFolderRequest(folderPath: folderPath)
        _ = try await networkManager.requestStatus(.configSourcesRemove, body: request)
    }

    /// 切换当前源文件夹
    /// - Parameter folderPath: 文件夹路径
    func switchSourceFolder(to folderPath: String) async throws {
        let request = SourceFolderRequest(folderPath: folderPath)
        _ = try await networkManager.requestStatus(.configSourcesSwitch, body: request)
    }

    // MARK: - 认证管理

    /// 上传平台认证信息
    /// - Parameters:
    ///   - platform: 平台标识（如 "x", "pixiv"）
    ///   - content: 认证内容（cookies 或 token）
    func uploadCredentials(platform: AuthPlatform, content: String) async throws {
        _ = try await networkManager.uploadText(.configCredentials(platform: platform.rawValue), content: content)
    }

    /// 删除平台认证信息
    /// - Parameter platform: 平台标识
    func deleteCredentials(platform: AuthPlatform) async throws {
        _ = try await networkManager.requestStatus(.configCredentials(platform: platform.rawValue))
    }

    /// 获取平台认证状态
    /// - Returns: 各平台的认证状态列表
    func getAuthStatus() async throws -> [PlatformCredential] {
        let config = try await getDownloadConfig()
        return [
            PlatformCredential(platform: .x, isConfigured: config.authStatus.x),
            PlatformCredential(platform: .pixiv, isConfigured: config.authStatus.pixiv)
        ]
    }

    // MARK: - 预设管理

    /// 加载预设
    /// - Parameter name: 预设名称
    /// - Returns: 加载预设响应
    func loadPreset(name: String) async throws -> LoadPresetResponse {
        let request = LoadPresetRequest(name: name)
        return try await networkManager.request(.configPresetLoad, body: request)
    }

    /// 获取所有预设列表
    /// - Returns: 预设列表
    func getPresets() async throws -> [Preset] {
        let state = try await getConfigState()
        return state.presets
    }
}
