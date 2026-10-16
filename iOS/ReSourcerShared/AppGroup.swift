//
//  AppGroup.swift
//  ReSourcerShared
//
//  App Group / Keychain Access Group 常量与跨进程共享存储。
//  主 App 与 Share Extension 共用。
//

import Foundation
import Security

/// App Group / URL Scheme / 后台会话标识
enum AppGroup {
    /// App Group 标识（须与 entitlements 一致）
    static let identifier = "group.app.resourcer.apple"

    /// Keychain Access Group（须与 entitlements 一致；运行时用 team 前缀解析）
    static let keychainAccessGroup = "925YHK2R4K.app.resourcer.apple"

    /// 主 App URL Scheme
    static let urlScheme = "resourcer"

    /// 下载页深链 host：`resourcer://download?url=...`
    static let downloadHost = "download"

    /// Share Extension 后台上传会话 ID（主 App 与 Extension 共用）
    static let backgroundUploadSessionId = "app.resourcer.apple.share-upload"

    /// App Group UserDefaults
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// App Group 容器目录
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// 后台上传暂存目录
    static var uploadStagingURL: URL? {
        guard let base = containerURL else { return nil }
        let dir = base.appendingPathComponent("ShareUploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Share 偏好（服务器 / 源 / 子文件夹）

/// Share Extension 上次选择（跨打开持久化）
struct ShareDestinationPreference: Codable, Equatable {
    var serverId: String
    var sourceFolder: String
    /// 相对源文件夹的子路径；空表示上传到源根
    var subfolder: String

    var targetFolder: String {
        if subfolder.isEmpty { return sourceFolder }
        return sourceFolder.hasSuffix("/")
            ? sourceFolder + subfolder
            : sourceFolder + "/" + subfolder
    }
}

// MARK: - ShareBridge

/// 主 App ↔ Share Extension 共享状态
enum ShareBridge {

    private enum Keys {
        static let servers = "share_saved_servers"
        static let currentServerId = "share_current_server_id"
        static let pendingDownloadURL = "share_pending_download_url"
        static let lastDestination = "share_last_destination"
        static let backgroundJobs = "share_background_upload_jobs"
        static func activeURL(forServerId id: String) -> String {
            "share_active_url_\(id)"
        }
    }

    // MARK: Servers（App Group 镜像；凭证优先 Keychain）

    /// 写入服务器列表到 App Group，并把 apiKey 同步到 Keychain Access Group
    static func syncServers(_ servers: [Server], currentServerId: String?) {
        // App Group 存不含密钥的元数据副本时仍保留 apiKey 作回退（旧 Extension / 无 Keychain 时）
        if let data = try? JSONEncoder().encode(servers) {
            AppGroup.defaults.set(data, forKey: Keys.servers)
        }
        if let currentServerId {
            AppGroup.defaults.set(currentServerId, forKey: Keys.currentServerId)
        } else {
            AppGroup.defaults.removeObject(forKey: Keys.currentServerId)
        }
        for server in servers {
            SharedKeychain.saveAPIKey(server.apiKey, forServerId: server.id)
        }
        // 清理已删除服务器的 Keychain 项
        let ids = Set(servers.map(\.id))
        for orphan in SharedKeychain.allStoredServerIds() where !ids.contains(orphan) {
            SharedKeychain.deleteAPIKey(forServerId: orphan)
        }
        // 清理已删除服务器的活跃地址
        for orphan in loadAllActiveURLServerIds() where !ids.contains(orphan) {
            clearActiveURL(forServerId: orphan)
        }
    }

    /// 同步某台服务器当前选用的活动地址（公网 / 局域网），供 Share Extension 直连
    static func syncActiveURL(_ urlString: String?, forServerId serverId: String) {
        let key = Keys.activeURL(forServerId: serverId)
        if let urlString, !urlString.isEmpty {
            AppGroup.defaults.set(urlString, forKey: key)
        } else {
            AppGroup.defaults.removeObject(forKey: key)
        }
    }

    static func loadActiveURL(forServerId serverId: String) -> String? {
        AppGroup.defaults.string(forKey: Keys.activeURL(forServerId: serverId))
    }

    static func clearActiveURL(forServerId serverId: String) {
        AppGroup.defaults.removeObject(forKey: Keys.activeURL(forServerId: serverId))
    }

    /// Extension 实际应连接的 base URL：优先 App Group 中的活跃地址
    static func effectiveBaseURL(for server: Server) -> String {
        if let active = loadActiveURL(forServerId: server.id), !active.isEmpty {
            return active
        }
        return server.baseURL
    }

    /// 连接候选：活跃地址优先，再主地址与备用（去重）
    static func connectionURLCandidates(for server: Server) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        func append(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, URL(string: trimmed)?.host != nil else { return }
            guard !seen.contains(trimmed) else { return }
            seen.insert(trimmed)
            ordered.append(trimmed)
        }
        append(effectiveBaseURL(for: server))
        for url in server.allURLs {
            append(url)
        }
        return ordered
    }

    /// 选择器文案：名称 + 有效 URL（公网 / 局域网可辨）
    static func sharePickerLabel(for server: Server) -> String {
        let urlPart = Server.displayURL(from: effectiveBaseURL(for: server))
        let trimmed = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return urlPart }
        return "\(trimmed) · \(urlPart)"
    }

    private static func loadAllActiveURLServerIds() -> [String] {
        let prefix = "share_active_url_"
        return AppGroup.defaults.dictionaryRepresentation().keys.compactMap { key in
            guard key.hasPrefix(prefix) else { return nil }
            return String(key.dropFirst(prefix.count))
        }
    }

    /// 读取可供 Extension 使用的服务器列表（Keychain 凭证优先）
    static func loadServers() -> [Server] {
        guard let data = AppGroup.defaults.data(forKey: Keys.servers),
              var servers = try? JSONDecoder().decode([Server].self, from: data) else {
            return []
        }
        for i in servers.indices {
            if let key = SharedKeychain.loadAPIKey(forServerId: servers[i].id), !key.isEmpty {
                servers[i].apiKey = key
            }
        }
        return servers
    }

    static func currentServerId() -> String? {
        AppGroup.defaults.string(forKey: Keys.currentServerId)
    }

    static func currentServer() -> Server? {
        let id = currentServerId()
        let servers = loadServers()
        if let id, let match = servers.first(where: { $0.id == id }) {
            return match
        }
        return servers.first
    }

    // MARK: Pending download URL（Flow A）

    static func setPendingDownloadURL(_ url: String?) {
        if let url, !url.isEmpty {
            AppGroup.defaults.set(url, forKey: Keys.pendingDownloadURL)
        } else {
            AppGroup.defaults.removeObject(forKey: Keys.pendingDownloadURL)
        }
    }

    static func consumePendingDownloadURL() -> String? {
        guard let url = AppGroup.defaults.string(forKey: Keys.pendingDownloadURL), !url.isEmpty else {
            return nil
        }
        AppGroup.defaults.removeObject(forKey: Keys.pendingDownloadURL)
        return url
    }

    static func peekPendingDownloadURL() -> String? {
        AppGroup.defaults.string(forKey: Keys.pendingDownloadURL)
    }

    /// 构建打开主 App 下载页的 URL：`resourcer://download?url=...`
    static func downloadDeepLink(url: String) -> URL? {
        var components = URLComponents()
        components.scheme = AppGroup.urlScheme
        components.host = AppGroup.downloadHost
        components.queryItems = [URLQueryItem(name: "url", value: url)]
        return components.url
    }

    /// 解析 `resourcer://download` 深链中的 url 参数
    static func parseDownloadDeepLink(_ url: URL) -> String? {
        guard url.scheme == AppGroup.urlScheme else { return nil }
        let host = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard host == AppGroup.downloadHost else { return nil }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let value = items.first(where: { $0.name == "url" })?.value,
           !value.isEmpty {
            return value
        }
        return peekPendingDownloadURL()
    }

    // MARK: Last destination

    static func saveLastDestination(_ preference: ShareDestinationPreference) {
        if let data = try? JSONEncoder().encode(preference) {
            AppGroup.defaults.set(data, forKey: Keys.lastDestination)
        }
    }

    static func loadLastDestination() -> ShareDestinationPreference? {
        guard let data = AppGroup.defaults.data(forKey: Keys.lastDestination) else { return nil }
        return try? JSONDecoder().decode(ShareDestinationPreference.self, from: data)
    }

    // MARK: Background upload job bookkeeping

    struct BackgroundUploadJob: Codable, Equatable {
        var id: String
        var serverId: String
        var baseURL: String
        var targetFolder: String
        var fileName: String
        var uploadId: String?
        var totalChunks: Int?
        var completedChunkIndexes: [Int]
        var localFilePath: String
        var kind: Kind
        var createdAt: Date

        enum Kind: String, Codable {
            case direct
            case chunked
        }
    }

    static func loadBackgroundJobs() -> [BackgroundUploadJob] {
        guard let data = AppGroup.defaults.data(forKey: Keys.backgroundJobs),
              let jobs = try? JSONDecoder().decode([BackgroundUploadJob].self, from: data) else {
            return []
        }
        return jobs
    }

    static func saveBackgroundJobs(_ jobs: [BackgroundUploadJob]) {
        if let data = try? JSONEncoder().encode(jobs) {
            AppGroup.defaults.set(data, forKey: Keys.backgroundJobs)
        }
    }

    static func upsertBackgroundJob(_ job: BackgroundUploadJob) {
        var jobs = loadBackgroundJobs()
        if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[idx] = job
        } else {
            jobs.append(job)
        }
        saveBackgroundJobs(jobs)
    }

    static func removeBackgroundJob(id: String) {
        var jobs = loadBackgroundJobs()
        jobs.removeAll { $0.id == id }
        saveBackgroundJobs(jobs)
    }
}

// MARK: - Shared Keychain

enum SharedKeychain {
    private static let service = "app.resourcer.apple.share-credentials"

    static func saveAPIKey(_ apiKey: String, forServerId serverId: String) {
        let account = serverId
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: AppGroup.keychainAccessGroup,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func loadAPIKey(forServerId serverId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverId,
            kSecAttrAccessGroup as String: AppGroup.keychainAccessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey(forServerId serverId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverId,
            kSecAttrAccessGroup as String: AppGroup.keychainAccessGroup,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func allStoredServerIds() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessGroup as String: AppGroup.keychainAccessGroup,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}
