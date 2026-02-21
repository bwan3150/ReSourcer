//
//  TagService.swift
//  ReSourcer
//
//  标签服务 - 标签 CRUD 与文件-标签关联
//

import Foundation

/// 标签操作服务
actor TagService {

    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    // MARK: - 标签 CRUD

    /// 获取源文件夹的所有标签
    func getTags(sourceFolder: String) async throws -> [Tag] {
        try await networkManager.request(.tagList(sourceFolder: sourceFolder))
    }

    /// 创建标签
    func createTag(sourceFolder: String, name: String, color: String? = nil) async throws -> Tag {
        let body = CreateTagRequest(sourceFolder: sourceFolder, name: name, color: color)
        return try await networkManager.request(.tagCreate, body: body)
    }

    /// 更新标签
    func updateTag(id: Int, name: String? = nil, color: String? = nil) async throws {
        let body = UpdateTagRequest(name: name, color: color)
        try await networkManager.requestVoid(.tagUpdate(id: id), body: body)
    }

    /// 删除标签
    func deleteTag(id: Int) async throws {
        try await networkManager.requestVoid(.tagDelete(id: id))
    }

    // MARK: - 文件-标签关联

    /// 获取文件的标签
    func getFileTags(fileUuid: String) async throws -> [Tag] {
        let response: FileTagsResponse = try await networkManager.request(.tagGetFileTags(fileUuid: fileUuid))
        return response.tags
    }

    /// 设置文件的标签（全量替换）
    func setFileTags(fileUuid: String, tagIds: [Int]) async throws {
        let body = FileTagRequest(fileUuid: fileUuid, tagIds: tagIds)
        try await networkManager.requestVoid(.tagSetFileTags, body: body)
    }

    /// 批量获取多个文件的标签
    func getFilesTags(fileUuids: [String]) async throws -> [FileTagsResponse] {
        let body = FilesTagsRequest(fileUuids: fileUuids)
        return try await networkManager.request(.tagGetFilesTags, body: body)
    }
}
