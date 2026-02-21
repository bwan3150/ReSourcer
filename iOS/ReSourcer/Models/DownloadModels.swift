//
//  DownloadModels.swift
//  ReSourcer
//
//  下载相关数据模型
//

import Foundation

/// 平台类型枚举
/// 注意：后端使用小写 serde rename
enum Platform: String, Codable, CaseIterable {
    case youtube = "youtube"
    case bilibili = "bilibili"
    case x = "x"
    case tiktok = "tiktok"
    case pixiv = "pixiv"
    case xiaohongshu = "xiaohongshu"
    case unknown = "unknown"

    /// 平台显示名称
    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .bilibili: return "哔哩哔哩"
        case .x: return "X (Twitter)"
        case .tiktok: return "TikTok"
        case .pixiv: return "Pixiv"
        case .xiaohongshu: return "小红书"
        case .unknown: return "未知"
        }
    }

    /// 平台图标名称（SF Symbols）
    var iconName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .bilibili: return "tv.fill"
        case .x: return "xmark.circle.fill"
        case .tiktok: return "music.note"
        case .pixiv: return "paintbrush.fill"
        case .xiaohongshu: return "book.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// 下载器类型枚举
/// 注意：后端使用小写 serde rename
enum DownloaderType: String, Codable {
    case ytDlp = "ytdlp"
    case pixivToolkit = "pixiv_toolkit"
    case unknown = "unknown"

    /// 显示名称
    var displayName: String {
        switch self {
        case .ytDlp: return "yt-dlp"
        case .pixivToolkit: return "Pixiv Toolkit"
        case .unknown: return "未知"
        }
    }
}

/// 下载任务状态枚举
/// 注意：后端使用小写 serde rename
enum DownloadTaskStatus: String, Codable {
    case pending = "pending"
    case downloading = "downloading"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"

    /// 是否为活跃状态
    var isActive: Bool {
        self == .pending || self == .downloading
    }

    /// 是否已完成（成功或失败）
    var isFinished: Bool {
        self == .completed || self == .failed || self == .cancelled
    }

    /// 状态显示颜色名称
    var colorName: String {
        switch self {
        case .pending: return "gray"
        case .downloading: return "blue"
        case .completed: return "green"
        case .failed: return "red"
        case .cancelled: return "orange"
        }
    }
}

/// 下载任务模型
struct DownloadTask: Identifiable, Codable, Equatable {

    /// 任务 ID
    let id: String

    /// 下载 URL
    let url: String

    /// 平台类型
    let platform: Platform

    /// 使用的下载器
    let downloader: DownloaderType

    /// 任务状态
    let status: DownloadTaskStatus

    /// 下载进度 (0-100)
    let progress: Float

    /// 下载速度（如 "1.2MB/s"）
    let speed: String?

    /// 预计剩余时间
    let eta: String?

    /// 保存文件夹
    let saveFolder: String

    /// 文件名
    let fileName: String?

    /// 文件完整路径
    let filePath: String?

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

    /// 格式化的创建时间（本地时区）
    var formattedCreatedAt: String {
        createdAt.toLocalDateTime
    }

    /// 构造用于预览的 FileInfo（仅已完成且有文件路径时有效）
    var previewFileInfo: FileInfo? {
        guard let filePath, let fileName else { return nil }
        let ext = fileName.contains(".")
            ? "." + (fileName.components(separatedBy: ".").last ?? "")
            : ""
        return FileInfo(
            uuid: nil,
            name: fileName,
            path: filePath,
            fileType: FileType.from(extension: ext),
            extension: ext,
            size: 0,
            created: createdAt,
            modified: createdAt,
            width: nil,
            height: nil,
            duration: nil
        )
    }
}

/// 下载任务列表响应
struct DownloadTasksResponse: Codable {
    let status: String
    let tasks: [DownloadTask]
}

/// 下载历史记录分页响应
struct DownloadHistoryResponse: Codable {
    let items: [DownloadTask]
    let total: Int
    let offset: Int
    let limit: Int
    let hasMore: Bool
}

/// URL 检测请求
struct UrlDetectRequest: Codable {
    let url: String
}

/// URL 检测响应
struct UrlDetectResponse: Codable {
    let platform: Platform
    let downloader: DownloaderType
    let confidence: Float
    let platformName: String
    let requiresAuth: Bool
}

/// 创建下载任务请求
struct CreateDownloadTaskRequest: Codable {
    let url: String
    let downloader: DownloaderType?
    let saveFolder: String
    let format: String?

    init(url: String, saveFolder: String, downloader: DownloaderType? = nil, format: String? = nil) {
        self.url = url
        self.saveFolder = saveFolder
        self.downloader = downloader
        self.format = format
    }
}

/// 创建下载任务响应
struct CreateDownloadTaskResponse: Codable {
    let status: String
    let taskId: String
    let message: String
}

/// 单个下载任务状态响应
struct DownloadTaskStatusResponse: Codable {
    let status: String
    let task: DownloadTask
}

// MARK: - ISO 8601 时间格式化

extension String {
    /// 将 ISO 8601 时间字符串转换为本地时区显示
    /// 例: "2026-02-08T09:51:50.776088830+00:00" → "2026.02.08 20:51:50 Australia/Sydney"
    var toLocalDateTime: String {
        // 去除纳秒精度的小数部分，确保 ISO8601DateFormatter 能解析
        let cleaned = self.replacingOccurrences(
            of: #"\.\d+"#,
            with: "",
            options: .regularExpression
        )

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        guard let date = isoFormatter.date(from: cleaned) else { return self }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "yyyy.MM.dd HH:mm:ss"
        displayFormatter.timeZone = .current

        let timeString = displayFormatter.string(from: date)
        let tzName = TimeZone.current.identifier

        return "\(timeString) \(tzName)"
    }
}
