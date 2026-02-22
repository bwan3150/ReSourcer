//
//  LocalStorageService.swift
//  ReSourcer
//
//  本地存储服务 - 使用 UserDefaults 管理本地数据
//

import Foundation

/// 本地存储服务 - 单例模式
final class LocalStorageService: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = LocalStorageService()

    private init() {}

    // MARK: - Keys

    private enum Keys {
        static let servers = "saved_servers"
        static let currentServerId = "current_server_id"
        static let isLoggedIn = "is_logged_in"
        static let lastActiveTime = "last_active_time"
        static let appSettings = "app_settings"
    }

    // MARK: - UserDefaults

    private var defaults: UserDefaults {
        UserDefaults.standard
    }

    // MARK: - Server Management

    /// 获取所有保存的服务器
    /// - Returns: 服务器列表
    func getServers() -> [Server] {
        guard let data = defaults.data(forKey: Keys.servers) else {
            return []
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([Server].self, from: data)
        } catch {
            print("Failed to decode servers: \(error)")
            return []
        }
    }

    /// 保存服务器列表
    /// - Parameter servers: 服务器列表
    /// - Returns: 是否保存成功
    @discardableResult
    func saveServers(_ servers: [Server]) -> Bool {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(servers)
            defaults.set(data, forKey: Keys.servers)
            return true
        } catch {
            print("Failed to encode servers: \(error)")
            return false
        }
    }

    /// 添加服务器
    /// - Parameter server: 要添加的服务器
    /// - Returns: 是否添加成功
    @discardableResult
    func addServer(_ server: Server) -> Bool {
        var servers = getServers()

        // 检查是否已存在相同 URL 的服务器
        if servers.contains(where: { $0.baseURL == server.baseURL }) {
            return false
        }

        servers.append(server)
        return saveServers(servers)
    }

    /// 更新服务器
    /// - Parameter server: 要更新的服务器
    /// - Returns: 是否更新成功
    @discardableResult
    func updateServer(_ server: Server) -> Bool {
        var servers = getServers()

        guard let index = servers.firstIndex(where: { $0.id == server.id }) else {
            return false
        }

        servers[index] = server
        return saveServers(servers)
    }

    /// 删除服务器
    /// - Parameter serverId: 服务器 ID
    /// - Returns: 是否删除成功
    @discardableResult
    func deleteServer(_ serverId: String) -> Bool {
        var servers = getServers()
        servers.removeAll { $0.id == serverId }

        // 如果删除的是当前服务器，清除当前服务器
        if getCurrentServerId() == serverId {
            clearCurrentServer()
        }

        return saveServers(servers)
    }

    /// 根据 ID 获取服务器
    /// - Parameter serverId: 服务器 ID
    /// - Returns: 服务器对象
    func getServer(by serverId: String) -> Server? {
        return getServers().first { $0.id == serverId }
    }

    // MARK: - Current Server

    /// 获取当前服务器 ID
    /// - Returns: 当前服务器 ID
    func getCurrentServerId() -> String? {
        return defaults.string(forKey: Keys.currentServerId)
    }

    /// 设置当前服务器
    /// - Parameter serverId: 服务器 ID
    /// - Returns: 是否设置成功
    @discardableResult
    func setCurrentServer(_ serverId: String) -> Bool {
        // 验证服务器存在
        guard getServer(by: serverId) != nil else {
            return false
        }

        defaults.set(serverId, forKey: Keys.currentServerId)
        return true
    }

    /// 获取当前服务器
    /// - Returns: 当前服务器对象
    func getCurrentServer() -> Server? {
        guard let serverId = getCurrentServerId() else {
            return nil
        }
        return getServer(by: serverId)
    }

    /// 清除当前服务器
    func clearCurrentServer() {
        defaults.removeObject(forKey: Keys.currentServerId)
    }

    // MARK: - Login Status

    /// 检查是否已登录
    /// - Returns: 是否已登录
    func isLoggedIn() -> Bool {
        return defaults.bool(forKey: Keys.isLoggedIn) && getCurrentServer() != nil
    }

    /// 设置登录状态
    /// - Parameter loggedIn: 是否已登录
    func setLoggedIn(_ loggedIn: Bool) {
        defaults.set(loggedIn, forKey: Keys.isLoggedIn)
    }

    /// 注销（清除登录状态但保留服务器配置）
    func logout() {
        setLoggedIn(false)
        clearCurrentServer()
    }

    // MARK: - App Settings

    /// 应用设置结构
    struct AppSettings: Codable {
        var thumbnailSize: Int = 300
        var autoRefreshInterval: TimeInterval = 30
        var enableNotifications: Bool = true
        var darkModePreference: DarkModePreference = .system
        var language: Language = .zh
        var ignoredFiles: [String] = [".DS_Store"]

        enum DarkModePreference: String, Codable {
            case light, dark, system
        }

        enum Language: String, Codable {
            case zh, en
        }
    }

    /// 获取应用设置
    /// - Returns: 应用设置
    func getAppSettings() -> AppSettings {
        guard let data = defaults.data(forKey: Keys.appSettings) else {
            return AppSettings()
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return AppSettings()
        }
    }

    /// 保存应用设置
    /// - Parameter settings: 应用设置
    /// - Returns: 是否保存成功
    @discardableResult
    func saveAppSettings(_ settings: AppSettings) -> Bool {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: Keys.appSettings)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Utilities

    /// 清除所有数据
    func clearAll() {
        defaults.removeObject(forKey: Keys.servers)
        defaults.removeObject(forKey: Keys.currentServerId)
        defaults.removeObject(forKey: Keys.isLoggedIn)
        defaults.removeObject(forKey: Keys.lastActiveTime)
        defaults.removeObject(forKey: Keys.appSettings)
    }

    /// 更新最后活跃时间
    func updateLastActiveTime() {
        defaults.set(Date(), forKey: Keys.lastActiveTime)
    }

    /// 获取最后活跃时间
    /// - Returns: 最后活跃时间
    func getLastActiveTime() -> Date? {
        return defaults.object(forKey: Keys.lastActiveTime) as? Date
    }
}
