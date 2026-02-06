//
//  ThumbnailCacheService.swift
//  ReSourcer
//
//  缩略图缓存服务 - 内存 + 磁盘双层缓存
//

import UIKit
import CryptoKit

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

        // L2: 磁盘缓存
        let filePath = diskPath(for: key)
        if let data = try? Data(contentsOf: filePath),
           let image = UIImage(data: data) {
            // 回填内存缓存
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

            // 异步写磁盘
            let filePath = diskPath(for: key)
            ioQueue.async {
                try? data.write(to: filePath)
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

    /// 清除磁盘缓存
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

    /// 计算磁盘缓存大小（字节）
    func diskCacheSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }

    /// 磁盘缓存文件数量
    func diskCacheCount() -> Int {
        let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        return contents?.count ?? 0
    }

    // MARK: - Private

    /// 生成缓存键（URL 的 SHA256 哈希）
    private func cacheKey(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// 磁盘缓存文件路径
    private func diskPath(for key: String) -> URL {
        return cacheDirectory.appendingPathComponent("\(key).jpg")
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
