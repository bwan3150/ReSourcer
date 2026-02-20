//
//  FolderModels.swift
//  ReSourcer
//
//  文件夹相关数据模型
//

import Foundation

/// 基础文件夹信息（子文件夹模式）
struct FolderInfo: Identifiable, Codable, Equatable {

    /// 文件夹名称
    let name: String

    /// 是否隐藏
    let hidden: Bool

    /// 文件计数
    let fileCount: Int

    // MARK: - Identifiable

    var id: String { name }

    // MARK: - Methods

    /// 复制并修改属性
    func with(hidden: Bool? = nil, fileCount: Int? = nil) -> FolderInfo {
        FolderInfo(
            name: self.name,
            hidden: hidden ?? self.hidden,
            fileCount: fileCount ?? self.fileCount
        )
    }
}

/// Gallery 样式文件夹信息
struct GalleryFolderInfo: Identifiable, Codable, Equatable {

    /// 文件夹名称
    let name: String

    /// 文件夹路径
    let path: String

    /// 是否为源文件夹
    let isSource: Bool

    /// 文件数量
    let fileCount: Int

    // MARK: - Identifiable

    var id: String { path }

    /// 显示名称（如果是源文件夹则显示完整路径末尾）
    var displayName: String {
        if isSource {
            return path.components(separatedBy: "/").last ?? name
        }
        return name
    }
}

/// Gallery 文件夹列表响应
struct GalleryFolderListResponse: Codable {
    let folders: [GalleryFolderInfo]
}

/// 文件夹创建请求
struct FolderCreateRequest: Codable {
    let folderName: String
}

/// 文件夹创建响应
struct FolderCreateResponse: Codable {
    let status: String
    let message: String
    let folderName: String
}

/// 文件夹排序请求
struct FolderReorderRequest: Codable {
    let sourceFolder: String
    let categoryOrder: [String]
}

/// 打开文件夹请求
struct FolderOpenRequest: Codable {
    let path: String
}

// MARK: - 目录浏览相关

/// 目录项
struct DirectoryItem: Identifiable, Codable, Equatable {

    /// 项目名称
    let name: String

    /// 完整路径
    let path: String

    /// 是否为目录
    let isDirectory: Bool

    // MARK: - Identifiable

    var id: String { path }

    /// 文件图标名称（SF Symbols）
    var iconName: String {
        if isDirectory {
            return "folder.fill"
        }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "heic":
            return "photo"
        case "mp4", "mov", "avi", "mkv":
            return "film"
        case "mp3", "wav", "aac", "flac":
            return "music.note"
        case "pdf":
            return "doc.fill"
        case "zip", "rar", "7z":
            return "doc.zipper"
        default:
            return "doc"
        }
    }
}

/// 目录浏览响应
struct BrowseResponse: Codable {

    /// 当前路径
    let currentPath: String

    /// 父目录路径
    let parentPath: String?

    /// 目录项列表
    let items: [DirectoryItem]
}

/// 目录浏览请求
struct BrowseRequest: Codable {
    let path: String?

    init(path: String? = nil) {
        self.path = path
    }
}

/// 创建目录请求
struct CreateDirectoryRequest: Codable {
    let parentPath: String
    let directoryName: String
}

/// 创建目录响应
struct CreateDirectoryResponse: Codable {
    let status: String
    let path: String
}
