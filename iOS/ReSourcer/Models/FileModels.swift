//
//  FileModels.swift
//  ReSourcer
//
//  文件相关数据模型
//

import Foundation

/// 文件类型枚举
/// 注意：后端使用 serde rename_all = "lowercase"，返回小写值
enum FileType: String, Codable, CaseIterable {
    case image = "image"
    case video = "video"
    case gif = "gif"
    case audio = "audio"
    case pdf = "pdf"
    case other = "other"

    /// 安全解码：未知类型 fallback 到 .other
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = FileType(rawValue: rawValue) ?? .other
    }

    /// 从扩展名推断文件类型
    static func from(extension ext: String) -> FileType {
        let lowercased = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch lowercased {
        case "jpg", "jpeg", "png", "webp", "bmp", "tiff", "svg", "heic", "heif", "avif":
            return .image
        case "mp4", "mov", "avi", "mkv", "flv", "wmv", "m4v", "webm":
            return .video
        case "gif":
            return .gif
        case "mp3", "wav", "aac", "flac", "m4a", "ogg", "wma":
            return .audio
        case "pdf":
            return .pdf
        default:
            return .other
        }
    }

    /// 是否为媒体文件（图片、视频、GIF、音频）
    var isMedia: Bool {
        switch self {
        case .image, .video, .gif, .audio:
            return true
        case .pdf, .other:
            return false
        }
    }
}

/// 文件信息模型
struct FileInfo: Identifiable, Codable, Equatable {

    /// 文件名（包含扩展名）
    let name: String

    /// 文件完整路径
    let path: String

    /// 文件类型
    let fileType: FileType

    /// 文件扩展名（如 ".jpg"）
    let `extension`: String

    /// 文件大小（字节）
    let size: UInt64

    /// 创建时间
    let created: String

    /// 修改时间
    let modified: String

    /// 图片宽度（仅图片/视频有效）
    let width: UInt32?

    /// 图片高度（仅图片/视频有效）
    let height: UInt32?

    /// 视频时长（秒，仅视频有效）
    let duration: Double?

    // MARK: - Identifiable

    var id: String { path }

    // MARK: - Computed Properties

    /// 是否为图片
    var isImage: Bool { fileType == .image }

    /// 是否为视频
    var isVideo: Bool { fileType == .video }

    /// 是否为 GIF
    var isGif: Bool { fileType == .gif }

    /// 是否为音频
    var isAudio: Bool { fileType == .audio }

    /// 是否为 PDF
    var isPdf: Bool { fileType == .pdf }

    /// 格式化后的文件大小
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// 文件名（不含扩展名）
    var baseName: String {
        if let dotIndex = name.lastIndex(of: ".") {
            return String(name[..<dotIndex])
        }
        return name
    }

    /// 纵横比
    var aspectRatio: Double? {
        guard let w = width, let h = height, h > 0 else { return nil }
        return Double(w) / Double(h)
    }

    /// 文件扩展名标签（大写，无点号），如 "PNG"、"MP4"、"GIF"
    var extensionLabel: String {
        let ext = `extension`.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if ext.isEmpty { return name.uppercased() }
        return ext.uppercased()
    }

    /// 格式化后的视频时长
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// 文件列表响应
struct FileListResponse: Codable {
    let files: [FileInfo]
}

/// 文件重命名请求
struct FileRenameRequest: Codable {
    let filePath: String
    let newName: String
}

/// 文件重命名响应
struct FileRenameResponse: Codable {
    let status: String
    let newPath: String
}

/// 文件移动请求
struct FileMoveRequest: Codable {
    let filePath: String
    let targetFolder: String
    let newName: String?

    init(filePath: String, targetFolder: String, newName: String? = nil) {
        self.filePath = filePath
        self.targetFolder = targetFolder
        self.newName = newName
    }
}

/// 文件移动响应
struct FileMoveResponse: Codable {
    let status: String
    let newPath: String
}
