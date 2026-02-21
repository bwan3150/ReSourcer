//
//  TagModels.swift
//  ReSourcer
//
//  标签相关数据模型
//

import Foundation

/// 标签
struct Tag: Identifiable, Codable, Equatable {
    let id: Int
    let sourceFolder: String
    let name: String
    let color: String
    let createdAt: String
}

/// 创建标签请求
struct CreateTagRequest: Codable {
    let sourceFolder: String
    let name: String
    let color: String?
}

/// 更新标签请求
struct UpdateTagRequest: Codable {
    let name: String?
    let color: String?
}

/// 设置文件标签请求
struct FileTagRequest: Codable {
    let fileUuid: String
    let tagIds: [Int]
}

/// 文件标签响应
struct FileTagsResponse: Codable {
    let fileUuid: String
    let tags: [Tag]
}

/// 批量获取文件标签请求
struct FilesTagsRequest: Codable {
    let fileUuids: [String]
}
