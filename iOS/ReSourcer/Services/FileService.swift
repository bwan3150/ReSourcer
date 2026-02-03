//
//  FileService.swift
//  ReSourcer
//
//  文件服务 - 处理文件信息、重命名和移动操作
//

import Foundation

/// 文件操作服务
actor FileService {

    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    // MARK: - Public Methods

    /// 获取指定文件夹内的所有媒体文件信息
    /// - Parameter folder: 文件夹路径
    /// - Returns: 文件信息列表
    func getFiles(in folder: String) async throws -> [FileInfo] {
        let response: FileListResponse = try await networkManager.request(.fileInfo(folder: folder))
        return response.files
    }

    /// 重命名文件
    /// - Parameters:
    ///   - filePath: 文件完整路径
    ///   - newName: 新文件名（不含路径）
    /// - Returns: 新文件路径
    func renameFile(at filePath: String, to newName: String) async throws -> String {
        let request = FileRenameRequest(filePath: filePath, newName: newName)
        let response: FileRenameResponse = try await networkManager.request(.fileRename, body: request)
        return response.newPath
    }

    /// 移动文件到其他文件夹
    /// - Parameters:
    ///   - filePath: 源文件完整路径
    ///   - targetFolder: 目标文件夹路径
    ///   - newName: 可选的新文件名
    /// - Returns: 新文件路径
    func moveFile(at filePath: String, to targetFolder: String, newName: String? = nil) async throws -> String {
        let request = FileMoveRequest(filePath: filePath, targetFolder: targetFolder, newName: newName)
        let response: FileMoveResponse = try await networkManager.request(.fileMove, body: request)
        return response.newPath
    }
}
