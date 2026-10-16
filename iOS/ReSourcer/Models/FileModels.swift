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

    /// 文件唯一标识符（索引系统分配，旧 API 返回时为 nil）
    let uuid: String?

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

    /// 下载来源 URL（仅下载的文件有值）
    let sourceUrl: String?

    // MARK: - Identifiable

    /// UUID 优先作为 ID，兼容旧 API 时回退到 path
    var id: String { uuid ?? path }

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

/// GPS 坐标（小数度，南纬/西经为负）
struct FileGpsCoords: Codable, Equatable {
    let lat: Double
    let lon: Double

    var formatted: String {
        let latHem = lat >= 0 ? "N" : "S"
        let lonHem = lon >= 0 ? "E" : "W"
        return String(format: "%.5f° %@, %.5f° %@", abs(lat), latHem, abs(lon), lonHem)
    }
}

/// 按路径读取的文件元数据（缺省字段由服务端省略，客户端隐藏）
struct FileMetadata: Codable, Equatable {
    let path: String
    let filename: String
    let format: String
    let size: UInt64
    let fileType: String?
    let width: UInt32?
    let height: UInt32?
    let duration: Double?
    let captureTime: String?
    let gps: FileGpsCoords?
    let created: String?
    let modified: String?
    let make: String?
    let model: String?
    let lens: String?
    let focalLengthMm: Double?
    let focalLength35mm: UInt32?
    let aperture: Double?
    let iso: UInt32?
    let shutterSpeed: String?
    let exposureCompensation: Double?
    let megapixels: Double?
    let codec: String?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var formattedDimensions: String? {
        guard let width, let height else { return nil }
        return "\(width) × \(height)"
    }

    var formattedDuration: String? {
        guard let duration else { return nil }
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// e.g. "Apple iPhone 15 Pro"
    var deviceLabel: String? {
        switch (make, model) {
        case let (m?, d?) where !m.isEmpty && !d.isEmpty:
            if d.lowercased().hasPrefix(m.lowercased()) { return d }
            return "\(m) \(d)"
        case let (m?, nil) where !m.isEmpty: return m
        case let (nil, d?) where !d.isEmpty: return d
        default: return nil
        }
    }

    /// Photos-style lens line, e.g. "Main Camera — 24 mm ƒ1.78"
    var lensLine: String? {
        var parts: [String] = []
        if let lens, !lens.isEmpty {
            let short = Self.shortenLens(lens)
            if !short.isEmpty { parts.append(short) }
        }
        var optics: [String] = []
        if let fl = focalLength35mm ?? focalLengthMm.map({ UInt32($0.rounded()) }) {
            optics.append("\(fl) mm")
        }
        if let aperture {
            optics.append(String(format: "ƒ%.2g", aperture))
        }
        if parts.isEmpty && optics.isEmpty { return nil }
        if parts.isEmpty { return optics.joined(separator: " ") }
        if optics.isEmpty { return parts[0] }
        return "\(parts[0]) — \(optics.joined(separator: " "))"
    }

    /// e.g. "24 MP • 5712 × 4284 • 3.6 MB"
    var resolutionSummary: String? {
        var parts: [String] = []
        if let megapixels {
            let mp = megapixels >= 10
                ? String(format: "%.0f MP", megapixels)
                : String(format: "%.1f MP", megapixels)
            parts.append(mp)
        }
        if let dims = formattedDimensions { parts.append(dims) }
        parts.append(formattedSize)
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var exifStripItems: [(label: String, value: String)] {
        var items: [(String, String)] = []
        if let iso { items.append(("ISO", "ISO\(iso)")) }
        if let fl = focalLength35mm ?? focalLengthMm.map({ UInt32($0.rounded()) }) {
            items.append(("Focal", "\(fl)mm"))
        }
        if let exposureCompensation {
            let v = exposureCompensation
            if abs(v) < 0.05 { items.append(("EV", "0ev")) }
            else { items.append(("EV", String(format: "%+.0fev", v))) }
        }
        if let aperture {
            items.append(("Aperture", String(format: "ƒ%.1f", aperture)))
        }
        if let shutterSpeed, !shutterSpeed.isEmpty {
            items.append(("Shutter", shutterSpeed.hasSuffix("s") ? shutterSpeed : "\(shutterSpeed)s"))
        }
        return items
    }

    private static func shortenLens(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("ultra") && lower.contains("wide") { return "Ultra Wide Camera" }
        if lower.contains("tele") { return "Telephoto Camera" }
        if lower.contains("front") || lower.contains("selfie") { return "Front Camera" }
        if lower.contains("back") || lower.contains("main") || lower.contains("wide") {
            return "Main Camera"
        }
        return raw
    }
}

/// 文件重命名请求
struct FileRenameRequest: Codable {
    let uuid: String
    let newName: String
}

/// 文件重命名响应
struct FileRenameResponse: Codable {
    let status: String
    let uuid: String
    let newPath: String
}

/// 文件移动请求
struct FileMoveRequest: Codable {
    let uuid: String
    let targetFolder: String
    let newName: String?

    init(uuid: String, targetFolder: String, newName: String? = nil) {
        self.uuid = uuid
        self.targetFolder = targetFolder
        self.newName = newName
    }
}

/// 文件移动响应
struct FileMoveResponse: Codable {
    let status: String
    let uuid: String
    let newPath: String
}

/// 文件删除请求（软删除到回收站）
struct FileDeleteRequest: Codable {
    let uuid: String
}

/// 批量移动文件请求
struct FileBatchMoveRequest: Codable {
    let uuids: [String]
    let targetFolder: String
}

/// 批量删除文件请求（软删除到回收站）
struct FileBatchDeleteRequest: Codable {
    let uuids: [String]
}

/// 批量操作成功单项
struct FileBatchSuccessItem: Codable {
    let uuid: String
    let newPath: String
}

/// 批量操作失败单项
struct FileBatchFailureItem: Codable {
    let uuid: String
    let error: String
}

/// 批量文件操作响应
struct FileBatchOperationResponse: Codable {
    let status: String
    let successCount: Int
    let failureCount: Int
    let succeeded: [FileBatchSuccessItem]
    let failed: [FileBatchFailureItem]
}

// MARK: - 索引系统模型

/// 服务端 IndexedFile（索引 API 原始返回格式）
struct IndexedFile: Codable {
    let uuid: String
    let fingerprint: String
    let currentPath: String?
    let folderPath: String
    let fileName: String
    let fileType: String
    let `extension`: String
    let fileSize: Int64
    let createdAt: String
    let modifiedAt: String
    let indexedAt: String
    let sourceUrl: String?
}

/// 索引文件分页响应
struct IndexedFilesResponse: Codable {
    let files: [IndexedFile]
    let total: Int
    let offset: Int
    let limit: Int
    let hasMore: Bool
}

/// 索引扫描请求
struct IndexerScanRequest: Codable {
    let sourceFolder: String
    let force: Bool
}

/// 索引扫描响应
struct IndexerScanResponse: Codable {
    let status: String
    let scannedFiles: UInt64?
    let scannedFolders: UInt64?
}

/// 索引状态（轮询用）
struct IndexerStatus: Codable {
    let isScanning: Bool
    let scannedFiles: UInt64
    let scannedFolders: UInt64
}

/// IndexedFile → FileInfo 转换
extension IndexedFile {
    func toFileInfo() -> FileInfo {
        FileInfo(
            uuid: uuid,
            name: fileName,
            path: currentPath ?? "",
            fileType: FileType(rawValue: fileType) ?? .other,
            extension: self.extension,
            size: UInt64(max(fileSize, 0)),
            created: createdAt,
            modified: modifiedAt,
            width: nil,
            height: nil,
            duration: nil,
            sourceUrl: sourceUrl
        )
    }
}
