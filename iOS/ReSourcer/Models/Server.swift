//
//  Server.swift
//  ReSourcer
//
//  服务器配置模型
//

import Foundation

/// 服务器状态枚举
enum ServerStatus: String, Codable {
    case online      // 在线
    case authError   // API Key 无效
    case offline     // 离线
    case checking    // 检查中
}

/// 服务器配置模型
struct Server: Identifiable, Codable, Equatable {

    /// 唯一标识符
    let id: String

    /// 服务器显示名称
    var name: String

    /// 服务器基础 URL（如 http://192.168.1.100:1234）
    var baseURL: String

    /// API Key 用于认证
    var apiKey: String

    /// 添加时间
    let addedAt: Date

    /// 服务器状态（不持久化）
    var status: ServerStatus = .checking

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKey, addedAt
    }

    // MARK: - Initialization

    init(id: String = UUID().uuidString, name: String, baseURL: String, apiKey: String, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.addedAt = addedAt
    }

    // MARK: - Computed Properties

    /// 获取 URL 对象
    var url: URL? {
        URL(string: baseURL)
    }

    /// 显示用的简短 URL（去掉 http:// 前缀）
    var displayURL: String {
        baseURL
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
    }

    // MARK: - Methods

    /// 复制并修改属性
    func with(
        name: String? = nil,
        baseURL: String? = nil,
        apiKey: String? = nil,
        status: ServerStatus? = nil
    ) -> Server {
        var copy = self
        if let name = name { copy.name = name }
        if let baseURL = baseURL { copy.baseURL = baseURL }
        if let apiKey = apiKey { copy.apiKey = apiKey }
        if let status = status { copy.status = status }
        return copy
    }
}
