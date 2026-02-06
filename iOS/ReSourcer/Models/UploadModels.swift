//
//  UploadModels.swift
//  ReSourcer
//
//  上传相关数据模型
//

import Foundation

/// 上传任务状态枚举
/// 注意：后端使用 serde rename_all = "lowercase"
enum UploadTaskStatus: String, Codable {
    case pending = "pending"
    case uploading = "uploading"
    case completed = "completed"
    case failed = "failed"

    /// 是否为活跃状态
    var isActive: Bool {
        self == .pending || self == .uploading
    }

    /// 是否已完成
    var isFinished: Bool {
        self == .completed || self == .failed
    }

    /// 状态显示颜色名称
    var colorName: String {
        switch self {
        case .pending: return "gray"
        case .uploading: return "blue"
        case .completed: return "green"
        case .failed: return "red"
        }
    }
}

/// 上传任务模型
struct UploadTask: Identifiable, Codable, Equatable {

    /// 任务 ID
    let id: String

    /// 文件名
    let fileName: String

    /// 文件大小（字节）
    let fileSize: UInt64

    /// 目标文件夹
    let targetFolder: String

    /// 任务状态
    let status: UploadTaskStatus

    /// 上传进度 (0-100)
    let progress: Float

    /// 已上传大小（字节）
    let uploadedSize: UInt64

    /// 错误信息
    let error: String?

    /// 创建时间
    let createdAt: String

    // MARK: - Computed Properties

    /// 是否可取消
    var canCancel: Bool { status.isActive }

    /// 是否可删除
    var canDelete: Bool { status.isFinished }

    /// 进度百分比显示
    var progressText: String {
        String(format: "%.1f%%", progress)
    }

    /// 格式化后的文件大小
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    /// 格式化后的已上传大小
    var formattedUploadedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(uploadedSize), countStyle: .file)
    }

    /// 进度描述
    var progressDescription: String {
        "\(formattedUploadedSize) / \(formattedFileSize)"
    }

    /// 格式化的创建时间（转换为本地时区）
    var formattedCreatedAt: String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: createdAt) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MM-dd HH:mm"
            return displayFormatter.string(from: date)
        }
        return createdAt
    }
}

/// 上传任务列表响应
struct UploadTasksResponse: Codable {
    let tasks: [UploadTask]
}

/// 上传任务创建响应
struct CreateUploadTaskResponse: Codable {
    let taskIds: [String]
    let message: String
}

/// 清除上传任务响应
struct ClearUploadTasksResponse: Codable {
    let message: String
    let clearedCount: Int
}

// MARK: - 待上传文件模型（本地使用）

/// 待上传的文件信息
struct PendingUploadFile: Identifiable {

    /// 唯一标识符
    let id: String

    /// 文件名
    let fileName: String

    /// 文件数据
    let data: Data

    /// MIME 类型
    let mimeType: String

    /// 文件大小
    var fileSize: Int { data.count }

    /// 格式化后的文件大小
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    init(fileName: String, data: Data, mimeType: String) {
        self.id = UUID().uuidString
        self.fileName = fileName
        self.data = data
        self.mimeType = mimeType
    }

    /// 从扩展名推断 MIME 类型
    static func mimeType(for extension: String) -> String {
        let ext = `extension`.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch ext {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic", "heif":
            return "image/heic"
        case "mp4":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "avi":
            return "video/x-msvideo"
        case "mkv":
            return "video/x-matroska"
        case "webm":
            return "video/webm"
        default:
            return "application/octet-stream"
        }
    }
}
