//
//  ConfigModels.swift
//  ReSourcer
//
//  配置相关数据模型
//

import Foundation

// MARK: - 全局配置

/// 全局配置响应
struct GlobalConfigResponse: Codable {
    let sourceFolder: String
    let hiddenFolders: [String]
}

/// App 配置响应
struct AppConfigResponse: Codable {
    let version: String
    let androidUrl: String?
    let iosUrl: String?
    let githubUrl: String?
}

// MARK: - 配置状态

/// 预设信息
struct Preset: Identifiable, Codable, Equatable {
    let name: String
    let categories: [String]

    var id: String { name }
}

/// 配置状态响应
struct ConfigStateResponse: Codable {
    let sourceFolder: String
    let hiddenFolders: [String]
    let backupSourceFolders: [String]
    let ignoredFolders: [String]?
    let presets: [Preset]
}

/// 保存配置请求
struct SaveConfigRequest: Codable {
    let sourceFolder: String
    let categories: [String]
    let hiddenFolders: [String]
    let ignoredFolders: [String]?
}

// MARK: - 下载器配置

/// 认证状态
struct AuthStatus: Codable, Equatable {
    /// X (Twitter) cookies 是否已配置
    let x: Bool

    /// Pixiv token 是否已配置
    let pixiv: Bool
}

/// 下载器配置响应
struct DownloadConfigResponse: Codable {
    let sourceFolder: String
    let hiddenFolders: [String]
    let useCookies: Bool
    let authStatus: AuthStatus
    let ytdlpVersion: String
}

/// 保存下载器配置请求
struct SaveDownloadConfigRequest: Codable {
    let sourceFolder: String
    let hiddenFolders: [String]
    let useCookies: Bool
}

// MARK: - 源文件夹管理

/// 源文件夹列表响应
struct SourceFoldersResponse: Codable {
    /// 当前活动的源文件夹
    let current: String

    /// 备用源文件夹列表
    let backups: [String]
}

/// 添加/移除/切换源文件夹请求
struct SourceFolderRequest: Codable {
    let folderPath: String
}

// MARK: - 预设管理

/// 加载预设请求
struct LoadPresetRequest: Codable {
    let name: String
}

/// 加载预设响应
struct LoadPresetResponse: Codable {
    let status: String
    let categories: [String]
    let presetName: String
}

/// 保存预设请求
struct SavePresetRequest: Codable {
    let name: String
}

/// 删除预设请求
struct DeletePresetRequest: Codable {
    let name: String
}

// MARK: - 健康检查

/// 健康检查响应
struct HealthResponse: Codable {
    let status: String
    let service: String
}
