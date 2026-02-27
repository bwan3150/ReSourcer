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

    /// 备用地址列表
    var alternateURLs: [String]

    /// API Key 用于认证
    var apiKey: String

    /// 添加时间
    let addedAt: Date

    /// 服务器状态（不持久化）
    var status: ServerStatus = .checking

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, alternateURLs, apiKey, addedAt
    }

    // MARK: - Initialization

    init(id: String = UUID().uuidString, name: String, baseURL: String, alternateURLs: [String] = [], apiKey: String, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.alternateURLs = alternateURLs
        self.apiKey = apiKey
        self.addedAt = addedAt
    }

    // 向后兼容：旧数据无 alternateURLs 时默认空数组
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        alternateURLs = try container.decodeIfPresent([String].self, forKey: .alternateURLs) ?? []
        apiKey = try container.decode(String.self, forKey: .apiKey)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
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

    /// 所有地址（主 + 备用）
    var allURLs: [String] { [baseURL] + alternateURLs }

    // MARK: - Methods

    /// 复制并修改属性
    func with(
        name: String? = nil,
        baseURL: String? = nil,
        alternateURLs: [String]? = nil,
        apiKey: String? = nil,
        status: ServerStatus? = nil
    ) -> Server {
        var copy = self
        if let name = name { copy.name = name }
        if let baseURL = baseURL { copy.baseURL = baseURL }
        if let alternateURLs = alternateURLs { copy.alternateURLs = alternateURLs }
        if let apiKey = apiKey { copy.apiKey = apiKey }
        if let status = status { copy.status = status }
        return copy
    }
}
