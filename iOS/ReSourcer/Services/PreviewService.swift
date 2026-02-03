//
//  PreviewService.swift
//  ReSourcer
//
//  预览服务 - 处理文件列表、缩略图和内容获取
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 预览服务
actor PreviewService {

    private let networkManager: NetworkManager

    /// 缩略图内存缓存
    private var thumbnailCache: [String: Data] = [:]

    /// 缓存大小限制（默认 50MB）
    private let maxCacheSize: Int = 50 * 1024 * 1024

    /// 当前缓存大小
    private var currentCacheSize: Int = 0

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    // MARK: - Public Methods

    /// 获取指定文件夹内的媒体文件列表
    /// - Parameter folder: 文件夹路径
    /// - Returns: 文件信息列表
    func getFiles(in folder: String) async throws -> [FileInfo] {
        let response: FileListResponse = try await networkManager.request(.previewFiles(folder: folder))
        return response.files
    }

    /// 获取文件缩略图数据
    /// - Parameters:
    ///   - path: 文件路径
    ///   - size: 缩略图尺寸（默认 300）
    ///   - useCache: 是否使用缓存（默认 true）
    /// - Returns: 缩略图数据（JPEG 格式）
    func getThumbnail(for path: String, size: Int = 300, useCache: Bool = true) async throws -> Data {
        let cacheKey = "\(path)_\(size)"

        // 检查缓存
        if useCache, let cached = thumbnailCache[cacheKey] {
            return cached
        }

        // 下载缩略图
        let data = try await networkManager.downloadData(.previewThumbnail(path: path, size: size))

        // 存入缓存
        if useCache {
            cacheThumbnail(data, for: cacheKey)
        }

        return data
    }

    /// 获取文件内容数据
    /// - Parameter path: 文件路径
    /// - Returns: 文件数据
    func getContent(for path: String) async throws -> Data {
        return try await networkManager.downloadData(.previewContent(path: path))
    }

    /// 获取缩略图 URL（用于直接显示）
    /// - Parameters:
    ///   - path: 文件路径
    ///   - size: 缩略图尺寸
    ///   - baseURL: 服务器基础 URL
    ///   - apiKey: API Key
    /// - Returns: 完整的缩略图 URL
    func getThumbnailURL(for path: String, size: Int = 300, baseURL: URL, apiKey: String) -> URL? {
        let encodedPath = path.urlEncoded
        let urlString = "\(baseURL.absoluteString)/api/preview/thumbnail?path=\(encodedPath)&size=\(size)&key=\(apiKey)"
        return URL(string: urlString)
    }

    /// 获取文件内容 URL（用于视频播放等）
    /// - Parameters:
    ///   - path: 文件路径
    ///   - baseURL: 服务器基础 URL
    ///   - apiKey: API Key
    /// - Returns: 完整的内容 URL
    func getContentURL(for path: String, baseURL: URL, apiKey: String) -> URL? {
        let encodedPath = path.urlEncoded
        let urlString = "\(baseURL.absoluteString)/api/preview/content/\(encodedPath)?key=\(apiKey)"
        return URL(string: urlString)
    }

    /// 清除缩略图缓存
    func clearThumbnailCache() {
        thumbnailCache.removeAll()
        currentCacheSize = 0
    }

    /// 获取当前缓存大小（字节）
    func getCacheSize() -> Int {
        return currentCacheSize
    }

    // MARK: - Private Methods

    /// 缓存缩略图，如果超出限制则清理旧缓存
    private func cacheThumbnail(_ data: Data, for key: String) {
        // 如果添加新数据会超出限制，清理一半缓存
        if currentCacheSize + data.count > maxCacheSize {
            let keysToRemove = Array(thumbnailCache.keys.prefix(thumbnailCache.count / 2))
            for key in keysToRemove {
                if let removed = thumbnailCache.removeValue(forKey: key) {
                    currentCacheSize -= removed.count
                }
            }
        }

        thumbnailCache[key] = data
        currentCacheSize += data.count
    }
}

// MARK: - UIImage Extension (iOS)

#if canImport(UIKit)
extension PreviewService {
    /// 获取缩略图 UIImage
    /// - Parameters:
    ///   - path: 文件路径
    ///   - size: 缩略图尺寸
    /// - Returns: UIImage 对象
    func getThumbnailImage(for path: String, size: Int = 300) async throws -> UIImage? {
        let data = try await getThumbnail(for: path, size: size)
        return UIImage(data: data)
    }

    /// 获取文件内容 UIImage（仅适用于图片文件）
    /// - Parameter path: 文件路径
    /// - Returns: UIImage 对象
    func getContentImage(for path: String) async throws -> UIImage? {
        let data = try await getContent(for: path)
        return UIImage(data: data)
    }
}
#endif
