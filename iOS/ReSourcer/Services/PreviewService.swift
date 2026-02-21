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

    /// 获取指定文件夹内的媒体文件列表（旧 API，ClassifierView 等仍可使用）
    /// - Parameter folder: 文件夹路径
    /// - Returns: 文件信息列表
    func getFiles(in folder: String) async throws -> [FileInfo] {
        let response: FileListResponse = try await networkManager.request(.previewFiles(folder: folder))
        return response.files
    }

    /// 分页获取索引文件列表（新 indexer API）
    /// - Parameters:
    ///   - folder: 文件夹路径
    ///   - offset: 分页偏移量
    ///   - limit: 每页数量
    ///   - fileType: 可选文件类型过滤
    ///   - sort: 可选排序方式
    /// - Returns: 索引文件分页响应
    func getFilesPaginated(in folder: String, offset: Int, limit: Int,
                           fileType: String? = nil, sort: String? = nil) async throws -> IndexedFilesResponse {
        return try await networkManager.request(
            .indexerFiles(folderPath: folder, offset: offset, limit: limit, fileType: fileType, sort: sort)
        )
    }

    /// 获取子文件夹列表（indexer API）
    /// - Parameters:
    ///   - parentPath: 父文件夹路径
    ///   - sourceFolder: 源文件夹路径
    /// - Returns: 索引文件夹数组
    func getIndexedFolders(parentPath: String?, sourceFolder: String?) async throws -> [IndexedFolder] {
        return try await networkManager.request(
            .indexerFolders(parentPath: parentPath, sourceFolder: sourceFolder)
        )
    }

    /// 获取面包屑路径（indexer API）
    /// - Parameter folderPath: 文件夹路径
    /// - Returns: 面包屑项数组
    func getBreadcrumb(folderPath: String) async throws -> [BreadcrumbItem] {
        return try await networkManager.request(
            .indexerBreadcrumb(folderPath: folderPath)
        )
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

    /// 获取缩略图 URL（基于文件路径，兼容旧 API 调用方）
    /// - Parameters:
    ///   - path: 文件路径
    ///   - size: 缩略图尺寸
    ///   - baseURL: 服务器基础 URL
    ///   - apiKey: API Key
    /// - Returns: 完整的缩略图 URL
    nonisolated func getThumbnailURL(for path: String, size: Int = 300, baseURL: URL, apiKey: String) -> URL? {
        let encodedPath = path.urlEncoded
        let urlString = "\(baseURL.absoluteString)/api/preview/thumbnail?path=\(encodedPath)&size=\(size)&key=\(apiKey)"
        return URL(string: urlString)
    }

    /// 获取缩略图 URL（基于 UUID，索引系统优先使用）
    /// - Parameters:
    ///   - uuid: 文件唯一标识符
    ///   - size: 缩略图尺寸
    ///   - baseURL: 服务器基础 URL
    ///   - apiKey: API Key
    ///   - sourceFolder: 源文件夹路径（仅本地缓存分层使用，不影响服务端）
    /// - Returns: 完整的缩略图 URL
    nonisolated func getThumbnailURL(uuid: String, size: Int = 300, baseURL: URL, apiKey: String, sourceFolder: String? = nil) -> URL? {
        let encodedUuid = uuid.urlEncoded
        var urlString = "\(baseURL.absoluteString)/api/preview/thumbnail?uuid=\(encodedUuid)&size=\(size)&key=\(apiKey)"
        if let sf = sourceFolder {
            urlString += "&sf=\(sf.urlEncoded)"
        }
        return URL(string: urlString)
    }

    /// 获取文件内容 URL（用于视频播放等）
    /// - Parameters:
    ///   - path: 文件路径
    ///   - baseURL: 服务器基础 URL
    ///   - apiKey: API Key
    /// - Returns: 完整的内容 URL
    nonisolated func getContentURL(for path: String, baseURL: URL, apiKey: String) -> URL? {
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
