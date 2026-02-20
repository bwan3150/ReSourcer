//
//  ThumbnailCacheService.swift
//  ReSourcer
//
//  缩略图缓存服务 - 内存 + 磁盘双层缓存
//  磁盘存储结构: thumbnails/{serverHash}/{folderHash}/{fileHash}.jpg
//

import UIKit
import CryptoKit

// MARK: - 缓存信息数据模型

/// 文件夹级缓存信息
struct ThumbnailFolderCacheInfo: Identifiable {
    let id = UUID()
    let folderHash: String
    let folderPath: String
    let displayName: String
    let fileCount: Int
    let totalSize: Int64
}

/// 服务器级缓存信息
struct ThumbnailServerCacheInfo: Identifiable {
    let id = UUID()
    let serverHash: String
    let serverURL: String
    let displayHost: String
    var folders: [ThumbnailFolderCacheInfo]
    var totalSize: Int64 { folders.reduce(0) { $0 + $1.totalSize } }
    var totalFileCount: Int { folders.reduce(0) { $0 + $1.fileCount } }
}

// MARK: - ThumbnailCacheService

/// 缩略图缓存服务 - 单例模式
final class ThumbnailCacheService: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = ThumbnailCacheService()

    // MARK: - L1 内存缓存

    private let memoryCache = NSCache<NSString, UIImage>()

    // MARK: - L2 磁盘缓存

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.resourcer.thumbnailcache.io", qos: .utility)

    /// 元数据文件名
    private static let metaFileName = "_meta.json"

    // MARK: - Init

    private init() {
        // Caches/thumbnails/
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("thumbnails", isDirectory: true)

        // 创建缓存目录
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // 配置内存缓存
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }

    // MARK: - 同步读取（内存 + 磁盘）

    /// 同步查找缓存图片（先内存后磁盘）
    /// - Parameter url: 缩略图 URL
    /// - Returns: 缓存的图片，未命中返回 nil
    func getImage(for url: URL) -> UIImage? {
        let key = cacheKey(for: url)

        // L1: 内存缓存
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // L2: 新分层磁盘路径
        let newPath = diskPath(for: key, url: url)
        if let data = try? Data(contentsOf: newPath),
           let image = UIImage(data: data) {
            let cost = data.count
            memoryCache.setObject(image, forKey: key as NSString, cost: cost)
            return image
        }

        // L3: 旧扁平磁盘路径（兼容迁移）
        let legacyPath = legacyDiskPath(for: key)
        if let data = try? Data(contentsOf: legacyPath),
           let image = UIImage(data: data) {
            let cost = data.count
            memoryCache.setObject(image, forKey: key as NSString, cost: cost)

            // 自动迁移到新路径
            let migrateTarget = newPath
            let migrateSource = legacyPath
            ioQueue.async { [weak self] in
                guard let self else { return }
                let dir = migrateTarget.deletingLastPathComponent()
                try? self.fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                try? data.write(to: migrateTarget)
                try? self.fileManager.removeItem(at: migrateSource)
                self.ensureMetadata(for: url)
            }
            return image
        }

        return nil
    }

    // MARK: - 异步加载（缓存 → 网络）

    /// 异步加载缩略图：查缓存 → 未命中则网络下载 → 写入缓存
    /// - Parameter url: 缩略图 URL
    /// - Returns: 加载的图片
    func loadImage(from url: URL) async -> UIImage? {
        // 先查缓存
        if let cached = getImage(for: url) {
            return cached
        }

        // 网络下载
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = UIImage(data: data) else {
                return nil
            }

            // 写入双层缓存
            let key = cacheKey(for: url)
            let cost = data.count
            memoryCache.setObject(image, forKey: key as NSString, cost: cost)

            // 异步写磁盘（新分层路径）
            let filePath = diskPath(for: key, url: url)
            ioQueue.async { [weak self] in
                guard let self else { return }
                let dir = filePath.deletingLastPathComponent()
                try? self.fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                try? data.write(to: filePath)
                self.ensureMetadata(for: url)
            }

            return image
        } catch {
            return nil
        }
    }

    // MARK: - 缓存管理

    /// 清除内存缓存
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    /// 清除磁盘缓存（全部，包括旧扁平文件和新分层目录）
    func clearDiskCache() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            try? self.fileManager.removeItem(at: self.cacheDirectory)
            try? self.fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        }
    }

    /// 清除全部缓存（内存 + 磁盘）
    func clearAll() {
        clearMemoryCache()
        clearDiskCache()
    }

    /// 计算磁盘缓存大小（字节），排除 _meta.json
    func diskCacheSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent != Self.metaFileName else { continue }
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               values.isRegularFile == true,
               let size = values.fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }

    /// 磁盘缓存文件数量，排除 _meta.json
    func diskCacheCount() -> Int {
        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent != Self.metaFileName else { continue }
            if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
               values.isRegularFile == true {
                count += 1
            }
        }
        return count
    }

    // MARK: - 分层查询

    /// 获取按服务器/文件夹分组的缓存统计信息
    func getCacheStatistics() -> [ThumbnailServerCacheInfo] {
        var servers: [ThumbnailServerCacheInfo] = []

        guard let serverDirs = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return servers }

        for serverDir in serverDirs {
            guard let isDir = try? serverDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDir else { continue }

            let sHash = serverDir.lastPathComponent
            // 读取服务器元数据
            let serverMeta = readMeta(at: serverDir)
            let serverURL = serverMeta["url"] ?? sHash
            let displayHost = serverMeta["host"] ?? sHash

            var folders: [ThumbnailFolderCacheInfo] = []

            guard let folderDirs = try? fileManager.contentsOfDirectory(
                at: serverDir,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) else { continue }

            for folderDir in folderDirs {
                guard let isFolderDir = try? folderDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                      isFolderDir else { continue }

                let fHash = folderDir.lastPathComponent
                let folderMeta = readMeta(at: folderDir)
                let folderPath = folderMeta["path"] ?? fHash
                let displayName = folderMeta["name"] ?? fHash

                // 统计文件夹内的文件
                var fileCount = 0
                var totalSize: Int64 = 0

                if let files = try? fileManager.contentsOfDirectory(
                    at: folderDir,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
                ) {
                    for file in files {
                        guard file.lastPathComponent != Self.metaFileName else { continue }
                        if let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                           values.isRegularFile == true {
                            fileCount += 1
                            totalSize += Int64(values.fileSize ?? 0)
                        }
                    }
                }

                if fileCount > 0 {
                    folders.append(ThumbnailFolderCacheInfo(
                        folderHash: fHash,
                        folderPath: folderPath,
                        displayName: displayName,
                        fileCount: fileCount,
                        totalSize: totalSize
                    ))
                }
            }

            if !folders.isEmpty {
                servers.append(ThumbnailServerCacheInfo(
                    serverHash: sHash,
                    serverURL: serverURL,
                    displayHost: displayHost,
                    folders: folders
                ))
            }
        }

        return servers
    }

    /// 旧版扁平缓存大小（根目录下的 .jpg 文件）
    func legacyCacheSize() -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }

        var totalSize: Int64 = 0
        for file in contents {
            guard file.pathExtension.lowercased() == "jpg" else { continue }
            if let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               values.isRegularFile == true {
                totalSize += Int64(values.fileSize ?? 0)
            }
        }
        return totalSize
    }

    /// 旧版扁平缓存文件数
    func legacyCacheCount() -> Int {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return 0 }

        return contents.filter { file in
            file.pathExtension.lowercased() == "jpg" &&
            (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.count
    }

    // MARK: - 分层清除

    /// 清除指定服务器的全部缓存
    func clearServerCache(serverHash: String) {
        let serverDir = cacheDirectory.appendingPathComponent(serverHash, isDirectory: true)
        ioQueue.async { [weak self] in
            try? self?.fileManager.removeItem(at: serverDir)
        }
        clearMemoryCache()
    }

    /// 清除指定服务器下指定文件夹的缓存
    func clearFolderCache(serverHash: String, folderHash: String) {
        let folderDir = cacheDirectory
            .appendingPathComponent(serverHash, isDirectory: true)
            .appendingPathComponent(folderHash, isDirectory: true)
        ioQueue.async { [weak self] in
            try? self?.fileManager.removeItem(at: folderDir)
        }
        clearMemoryCache()
    }

    /// 清除旧版扁平缓存（根目录下的 .jpg 文件）
    func clearLegacyCache() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            guard let contents = try? self.fileManager.contentsOfDirectory(
                at: self.cacheDirectory,
                includingPropertiesForKeys: [.isRegularFileKey]
            ) else { return }

            for file in contents {
                if file.pathExtension.lowercased() == "jpg",
                   let values = try? file.resourceValues(forKeys: [.isRegularFileKey]),
                   values.isRegularFile == true {
                    try? self.fileManager.removeItem(at: file)
                }
            }
        }
        clearMemoryCache()
    }

    // MARK: - Private: URL 解析

    /// 从缩略图 URL 解析出 serverBase 和 folderPath
    /// URL 格式: {baseURL}/api/preview/thumbnail?path=xxx&size=300&key=xxx
    private func parseThumbnailURL(_ url: URL) -> (serverBase: String, folderPath: String)? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        // 构建 serverBase: scheme://host:port
        guard let scheme = components.scheme, let host = components.host else { return nil }
        var serverBase = "\(scheme)://\(host)"
        if let port = components.port {
            serverBase += ":\(port)"
        }

        // 从 query 参数中提取 path
        guard let queryItems = components.queryItems,
              let pathParam = queryItems.first(where: { $0.name == "path" })?.value else {
            return (serverBase, "/")
        }

        // 取目录部分
        let folderPath: String
        if let lastSlash = pathParam.lastIndex(of: "/") {
            let dir = String(pathParam[pathParam.startIndex..<lastSlash])
            folderPath = dir.isEmpty ? "/" : dir
        } else {
            folderPath = "/"
        }

        return (serverBase, folderPath)
    }

    /// 生成 SHA256 哈希的前 16 个字符
    private func shortHash(for string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(8).compactMap { String(format: "%02x", $0) }.joined() // 8 bytes = 16 hex chars
    }

    // MARK: - Private: 磁盘路径

    /// 生成缓存键（URL 的 SHA256 哈希，64 字符）
    private func cacheKey(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// 新分层磁盘路径: thumbnails/{serverHash}/{folderHash}/{fileHash}.jpg
    private func diskPath(for key: String, url: URL) -> URL {
        guard let parsed = parseThumbnailURL(url) else {
            // 解析失败降级到根目录
            return cacheDirectory.appendingPathComponent("\(key).jpg")
        }

        let sHash = shortHash(for: parsed.serverBase)
        let fHash = shortHash(for: parsed.folderPath)

        return cacheDirectory
            .appendingPathComponent(sHash, isDirectory: true)
            .appendingPathComponent(fHash, isDirectory: true)
            .appendingPathComponent("\(key).jpg")
    }

    /// 旧扁平磁盘路径: thumbnails/{fileHash}.jpg
    private func legacyDiskPath(for key: String) -> URL {
        return cacheDirectory.appendingPathComponent("\(key).jpg")
    }

    // MARK: - Private: 元数据

    /// 在服务器和文件夹目录下写入 _meta.json（如果不存在）
    private func ensureMetadata(for url: URL) {
        guard let parsed = parseThumbnailURL(url) else { return }

        let sHash = shortHash(for: parsed.serverBase)
        let fHash = shortHash(for: parsed.folderPath)

        let serverDir = cacheDirectory.appendingPathComponent(sHash, isDirectory: true)
        let folderDir = serverDir.appendingPathComponent(fHash, isDirectory: true)

        // 服务器 _meta.json
        let serverMetaPath = serverDir.appendingPathComponent(Self.metaFileName)
        if !fileManager.fileExists(atPath: serverMetaPath.path) {
            // 提取 host 显示名
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var displayHost = components?.host ?? sHash
            if let port = components?.port {
                displayHost += ":\(port)"
            }

            let serverMeta: [String: String] = [
                "url": parsed.serverBase,
                "host": displayHost
            ]
            if let data = try? JSONSerialization.data(withJSONObject: serverMeta) {
                try? data.write(to: serverMetaPath)
            }
        }

        // 文件夹 _meta.json
        let folderMetaPath = folderDir.appendingPathComponent(Self.metaFileName)
        if !fileManager.fileExists(atPath: folderMetaPath.path) {
            // 显示名取最后一个路径分量
            let displayName: String
            if parsed.folderPath == "/" {
                displayName = "根目录"
            } else if let lastComponent = parsed.folderPath.split(separator: "/").last {
                displayName = String(lastComponent)
            } else {
                displayName = parsed.folderPath
            }

            let folderMeta: [String: String] = [
                "path": parsed.folderPath,
                "name": displayName
            ]
            if let data = try? JSONSerialization.data(withJSONObject: folderMeta) {
                try? data.write(to: folderMetaPath)
            }
        }
    }

    /// 读取目录下的 _meta.json
    private func readMeta(at directory: URL) -> [String: String] {
        let metaPath = directory.appendingPathComponent(Self.metaFileName)
        guard let data = try? Data(contentsOf: metaPath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }
}

// MARK: - 缓存工具方法

extension ThumbnailCacheService {

    /// 格式化缓存大小为可读字符串
    static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 获取视频缓存大小（tmp 目录）
    static func videoCacheSize() -> Int64 {
        let tmpDir = FileManager.default.temporaryDirectory
        return directorySize(at: tmpDir, extensions: ["mp4", "mov", "avi", "mkv", "webm"])
    }

    /// 获取网络缓存大小
    static func networkCacheSize() -> Int64 {
        return Int64(URLCache.shared.currentDiskUsage)
    }

    /// 获取 App 临时文件大小（排除视频）
    static func appTempSize() -> Int64 {
        let tmpDir = FileManager.default.temporaryDirectory
        let totalSize = directorySize(at: tmpDir)
        let videoSize = videoCacheSize()
        return max(0, totalSize - videoSize)
    }

    /// 清除视频缓存
    static func clearVideoCache() {
        let tmpDir = FileManager.default.temporaryDirectory
        clearFiles(in: tmpDir, extensions: ["mp4", "mov", "avi", "mkv", "webm"])
    }

    /// 清除网络缓存
    static func clearNetworkCache() {
        URLCache.shared.removeAllCachedResponses()
    }

    /// 清除 App 临时文件
    static func clearAppTemp() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil) else { return }
        for url in contents {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Private Helpers

    private static func directorySize(at url: URL, extensions: [String]? = nil) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let exts = extensions {
                guard exts.contains(fileURL.pathExtension.lowercased()) else { continue }
            }
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }

    private static func clearFiles(in directory: URL, extensions: [String]) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            if extensions.contains(fileURL.pathExtension.lowercased()) {
                try? fm.removeItem(at: fileURL)
            }
        }
    }
}
