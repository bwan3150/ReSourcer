//
//  FolderService.swift
//  ReSourcer
//
//  文件夹服务 - 处理文件夹列表、创建和排序操作
//

import Foundation

/// 文件夹操作服务
actor FolderService {

    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    // MARK: - Public Methods

    /// 获取指定源文件夹的子文件夹列表
    /// - Parameter sourceFolder: 源文件夹路径
    /// - Returns: 文件夹信息列表
    func getSubfolders(in sourceFolder: String) async throws -> [FolderInfo] {
        return try await networkManager.request(.folderList(sourceFolder: sourceFolder))
    }

    /// 获取 Gallery 样式的文件夹列表（源文件夹 + 分类）
    /// - Returns: Gallery 文件夹列表
    func getGalleryFolders() async throws -> [GalleryFolderInfo] {
        let response: GalleryFolderListResponse = try await networkManager.request(.folderList(sourceFolder: nil))
        return response.folders
    }

    /// 创建新文件夹
    /// - Parameter folderName: 文件夹名称
    /// - Returns: 创建的文件夹名称
    func createFolder(name folderName: String) async throws -> String {
        let request = FolderCreateRequest(folderName: folderName)
        let response: FolderCreateResponse = try await networkManager.request(.folderCreate, body: request)
        return response.folderName
    }

    /// 保存子文件夹排序（支持任意层级）
    /// - Parameters:
    ///   - folderPath: 当前文件夹路径
    ///   - order: 子文件夹名称顺序数组
    func saveFolderOrder(folderPath: String, order: [String]) async throws {
        let request = FolderReorderRequest(folderPath: folderPath, order: order)
        _ = try await networkManager.requestStatus(.folderReorder, body: request)
    }

    /// 在系统中打开文件夹
    /// - Parameter path: 文件夹路径
    func openFolder(at path: String) async throws {
        let request = FolderOpenRequest(path: path)
        _ = try await networkManager.requestStatus(.folderOpen, body: request)
    }
}
