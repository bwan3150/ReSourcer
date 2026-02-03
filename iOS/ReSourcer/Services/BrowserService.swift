//
//  BrowserService.swift
//  ReSourcer
//
//  文件系统浏览服务 - 处理目录浏览和创建
//

import Foundation

/// 文件系统浏览服务
actor BrowserService {

    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    // MARK: - Public Methods

    /// 浏览目录
    /// - Parameter path: 目录路径（nil 表示从用户主目录开始）
    /// - Returns: 浏览响应，包含当前路径、父路径和目录项
    func browse(path: String? = nil) async throws -> BrowseResponse {
        let request = BrowseRequest(path: path)
        return try await networkManager.request(.browserBrowse, body: request)
    }

    /// 创建新目录
    /// - Parameters:
    ///   - parentPath: 父目录路径
    ///   - directoryName: 新目录名称
    /// - Returns: 创建的目录路径
    func createDirectory(in parentPath: String, name directoryName: String) async throws -> String {
        let request = CreateDirectoryRequest(parentPath: parentPath, directoryName: directoryName)
        let response: CreateDirectoryResponse = try await networkManager.request(.browserCreate, body: request)
        return response.path
    }

    // MARK: - 便捷方法

    /// 从用户主目录开始浏览
    /// - Returns: 浏览响应
    func browseHome() async throws -> BrowseResponse {
        return try await browse(path: nil)
    }

    /// 浏览父目录
    /// - Parameter currentPath: 当前目录路径
    /// - Returns: 父目录的浏览响应，如果已在根目录则返回 nil
    func browseParent(from currentPath: String) async throws -> BrowseResponse? {
        let response = try await browse(path: currentPath)
        guard let parentPath = response.parentPath else {
            return nil
        }
        return try await browse(path: parentPath)
    }

    /// 获取目录中的子目录列表
    /// - Parameter path: 目录路径
    /// - Returns: 仅包含目录的项目列表
    func getSubdirectories(in path: String) async throws -> [DirectoryItem] {
        let response = try await browse(path: path)
        return response.items.filter { $0.isDirectory }
    }

    /// 获取目录中的文件列表
    /// - Parameter path: 目录路径
    /// - Returns: 仅包含文件的项目列表
    func getFiles(in path: String) async throws -> [DirectoryItem] {
        let response = try await browse(path: path)
        return response.items.filter { !$0.isDirectory }
    }
}
