//
//  ThumbnailCacheService.swift
//  ReSourcer
//
//  缩略图缓存服务 - 内存 + 磁盘双层缓存
//  磁盘存储结构: thumbnails/{serverHash}/{uuidPrefix}/{fileHash}.jpg
//

import UIKit
import CryptoKit

// MARK: - 缓存信息数据模型

/// 源文件夹级缓存信息
struct ThumbnailSourceFolderCacheInfo: Identifiable {
    let folderHash: String
    let folderName: String
    var fileCount: Int
    var totalSize: Int64
    var id: String { folderHash }
}

/// 服务器级缓存信息
struct ThumbnailServerCacheInfo: Identifiable {
    let serverHash: String
    let serverURL: String
    let displayHost: String
    var sourceFolders: [ThumbnailSourceFolderCacheInfo]
    var fileCount: Int { sourceFolders.reduce(0) { $0 + $1.fileCount } }
    var totalSize: Int64 { sourceFolders.reduce(0) { $0 + $1.totalSize } }
    var id: String { serverHash }
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

        // L2: 分层磁盘路径
        let path = diskPath(for: key, url: url)
        if let data = try? Data(contentsOf: path),
           let image = UIImage(data: data) {
            let cost = data.count
            memoryCache.setObject(image, forKey: key as NSString, cost: cost)
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

    // MARK: - 缓存统计

    /// 获取按服务器 > 源文件夹分组的缓存统计信息
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
            let serverMeta = readMeta(at: serverDir)
            let serverURL = serverMeta["url"] ?? sHash
            let displayHost = serverMeta["host"] ?? sHash

            // 扫描子目录，判断是否有 sourceFolder 层
            var sourceFolders: [ThumbnailSourceFolderCacheInfo] = []
            var ungroupedFileCount = 0
            var ungroupedSize: Int64 = 0

            if let subDirs = try? fileManager.contentsOfDirectory(
                at: serverDir,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) {
                for subDir in subDirs {
                    guard subDir.lastPathComponent != Self.metaFileName else { continue }
                    guard let subIsDir = try? subDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                          subIsDir else { continue }

                    let subHash = subDir.lastPathComponent
                    let subMeta = readMeta(at: subDir)

                    if subMeta["sourceFolder"] != nil {
                        // 这是 sourceFolderHash 层
                        let folderName = subMeta["name"] ?? subHash
                        var sfFileCount = 0
                        var sfSize: Int64 = 0

                        if let enumerator = fileManager.enumerator(
                            at: subDir,
                            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                            options: [.skipsHiddenFiles]
                        ) {
                            for case let fileURL as URL in enumerator {
                                guard fileURL.lastPathComponent != Self.metaFileName else { continue }
                                if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                                   values.isRegularFile == true {
                                    sfFileCount += 1
                                    sfSize += Int64(values.fileSize ?? 0)
                                }
                            }
                        }

                        if sfFileCount > 0 {
                            sourceFolders.append(ThumbnailSourceFolderCacheInfo(
                                folderHash: subHash,
                                folderName: folderName,
                                fileCount: sfFileCount,
                                totalSize: sfSize
                            ))
                        }
                    } else {
                        // 旧格式的 bucketKey 目录（无 sourceFolder 分层），归入未分组
                        if let enumerator = fileManager.enumerator(
                            at: subDir,
                            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                            options: [.skipsHiddenFiles]
                        ) {
                            for case let fileURL as URL in enumerator {
                                guard fileURL.lastPathComponent != Self.metaFileName else { continue }
                                if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                                   values.isRegularFile == true {
                                    ungroupedFileCount += 1
                                    ungroupedSize += Int64(values.fileSize ?? 0)
                                }
                            }
                        }
                    }
                }
            }

            // 未分组的缓存文件归入一个 "未分组" 条目
            if ungroupedFileCount > 0 {
                sourceFolders.insert(ThumbnailSourceFolderCacheInfo(
                    folderHash: "_ungrouped",
                    folderName: "未分组",
                    fileCount: ungroupedFileCount,
                    totalSize: ungroupedSize
                ), at: 0)
            }

            if !sourceFolders.isEmpty {
                servers.append(ThumbnailServerCacheInfo(
                    serverHash: sHash,
                    serverURL: serverURL,
                    displayHost: displayHost,
                    sourceFolders: sourceFolders
                ))
            }
        }

        return servers
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

    /// 清除指定服务器下某个源文件夹的缓存
    func clearSourceFolderCache(serverHash: String, folderHash: String) {
        if folderHash == "_ungrouped" {
            // 清除旧格式的未分组缓存：删除 serverDir 下不含 _meta.json(sourceFolder) 的子目录
            let serverDir = cacheDirectory.appendingPathComponent(serverHash, isDirectory: true)
            ioQueue.async { [weak self] in
                guard let self else { return }
                if let subDirs = try? self.fileManager.contentsOfDirectory(
                    at: serverDir, includingPropertiesForKeys: [.isDirectoryKey]
                ) {
                    for subDir in subDirs {
                        guard subDir.lastPathComponent != Self.metaFileName else { continue }
                        guard let isDir = try? subDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                              isDir else { continue }
                        let meta = self.readMeta(at: subDir)
                        if meta["sourceFolder"] == nil {
                            try? self.fileManager.removeItem(at: subDir)
                        }
                    }
                }
            }
        } else {
            let sfDir = cacheDirectory
                .appendingPathComponent(serverHash, isDirectory: true)
                .appendingPathComponent(folderHash, isDirectory: true)
            ioQueue.async { [weak self] in
                try? self?.fileManager.removeItem(at: sfDir)
            }
        }
        clearMemoryCache()
    }

    // MARK: - Private: URL 解析

    /// 从缩略图 URL 解析出 serverBase、sourceFolderHash 和 bucketKey（用于磁盘分桶）
    /// URL 格式:
    ///   UUID: {baseURL}/api/preview/thumbnail?uuid=xxx&size=300&key=xxx&sf=xxx&sid=xxx
    ///   Path: {baseURL}/api/preview/thumbnail?path=xxx&size=300&key=xxx&sid=xxx
    private func parseThumbnailURL(_ url: URL) -> (serverBase: String, sourceFolder: String?, bucketKey: String)? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        // 优先使用 sid（server ID）做目录分层，实现跨地址缓存共享
        // 若无 sid，降级到基于 URL 的 serverBase
        let serverBase: String
        if let sid = components.queryItems?.first(where: { $0.name == "sid" })?.value, !sid.isEmpty {
            serverBase = sid
        } else {
            guard let scheme = components.scheme, let host = components.host else { return nil }
            var base = "\(scheme)://\(host)"
            if let port = components.port {
                base += ":\(port)"
            }
            serverBase = base
        }

        // 提取 sf（source folder）参数
        let sourceFolder = components.queryItems?.first(where: { $0.name == "sf" })?.value

        // 优先使用 uuid 参数的前 2 字符做分桶
        if let queryItems = components.queryItems,
           let uuidParam = queryItems.first(where: { $0.name == "uuid" })?.value,
           uuidParam.count >= 2 {
            let prefix = String(uuidParam.prefix(2))
            return (serverBase, sourceFolder, prefix)
        }

        // 兼容 path 参数：取目录部分的哈希前 2 字符
        if let queryItems = components.queryItems,
           let pathParam = queryItems.first(where: { $0.name == "path" })?.value {
            let folderPath: String
            if let lastSlash = pathParam.lastIndex(of: "/") {
                let dir = String(pathParam[pathParam.startIndex..<lastSlash])
                folderPath = dir.isEmpty ? "/" : dir
            } else {
                folderPath = "/"
            }
            let fHash = shortHash(for: folderPath)
            let prefix = String(fHash.prefix(2))
            return (serverBase, sourceFolder, prefix)
        }

        return (serverBase, sourceFolder, "00")
    }

    /// 生成 SHA256 哈希的前 16 个字符
    private func shortHash(for string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(8).compactMap { String(format: "%02x", $0) }.joined() // 8 bytes = 16 hex chars
    }

    // MARK: - Private: 磁盘路径

    /// 生成缓存键（基于 uuid/path + size，不含 baseURL，实现跨地址缓存共享）
    private func cacheKey(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            // 解析失败降级到完整 URL 哈希
            let data = Data(url.absoluteString.utf8)
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        }

        // 只取 uuid/path + size 参数计算哈希（不含 baseURL、key、sid）
        let relevantParts = queryItems
            .filter { ["uuid", "path", "size"].contains($0.name) }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")

        let data = Data(relevantParts.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// 分层磁盘路径: thumbnails/{serverHash}/{sourceFolderHash}/{bucketKey}/{fileHash}.jpg
    private func diskPath(for key: String, url: URL) -> URL {
        guard let parsed = parseThumbnailURL(url) else {
            // 解析失败降级到根目录
            return cacheDirectory.appendingPathComponent("\(key).jpg")
        }

        let sHash = shortHash(for: parsed.serverBase)
        var base = cacheDirectory.appendingPathComponent(sHash, isDirectory: true)

        // 有 sourceFolder 时加入 sourceFolderHash 层
        if let sf = parsed.sourceFolder {
            let sfHash = String(shortHash(for: sf).prefix(8))
            base = base.appendingPathComponent(sfHash, isDirectory: true)
        }

        return base
            .appendingPathComponent(parsed.bucketKey, isDirectory: true)
            .appendingPathComponent("\(key).jpg")
    }

    // MARK: - Private: 元数据

    /// 在服务器目录和源文件夹目录下写入 _meta.json（如果不存在）
    private func ensureMetadata(for url: URL) {
        guard let parsed = parseThumbnailURL(url) else { return }

        let sHash = shortHash(for: parsed.serverBase)
        let serverDir = cacheDirectory.appendingPathComponent(sHash, isDirectory: true)

        // 服务器 _meta.json
        let serverMetaPath = serverDir.appendingPathComponent(Self.metaFileName)
        if !fileManager.fileExists(atPath: serverMetaPath.path) {
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

        // 源文件夹 _meta.json
        if let sf = parsed.sourceFolder {
            let sfHash = String(shortHash(for: sf).prefix(8))
            let sfDir = serverDir.appendingPathComponent(sfHash, isDirectory: true)
            let sfMetaPath = sfDir.appendingPathComponent(Self.metaFileName)
            if !fileManager.fileExists(atPath: sfMetaPath.path) {
                try? fileManager.createDirectory(at: sfDir, withIntermediateDirectories: true)
                let sfName = sf.components(separatedBy: "/").last ?? sf
                let sfMeta: [String: String] = [
                    "sourceFolder": sf,
                    "name": sfName
                ]
                if let data = try? JSONSerialization.data(withJSONObject: sfMeta) {
                    try? data.write(to: sfMetaPath)
                }
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
