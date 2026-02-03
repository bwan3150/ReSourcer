//
//  APIEndpoint.swift
//  ReSourcer
//
//  API 端点定义
//

import Foundation

/// HTTP 请求方法
enum HTTPMethod: String {
    case GET
    case POST
    case PUT
    case DELETE
}

/// API 端点枚举 - 定义所有可用的 API 路由
enum APIEndpoint {

    // MARK: - Auth 认证相关
    case authVerify                          // POST /api/auth/verify
    case authCheck                           // GET  /api/auth/check

    // MARK: - Global 全局配置
    case health                              // GET  /api/health
    case config                              // GET  /api/config
    case appConfig                           // GET  /api/app

    // MARK: - File 文件操作
    case fileInfo(folder: String)            // GET  /api/file/info?folder=
    case fileRename                          // POST /api/file/rename
    case fileMove                            // POST /api/file/move

    // MARK: - Folder 文件夹操作
    case folderList(sourceFolder: String?)   // GET  /api/folder/list
    case folderCreate                        // POST /api/folder/create
    case folderReorder                       // POST /api/folder/reorder
    case folderOpen                          // POST /api/folder/open

    // MARK: - Transfer/Download 下载相关
    case downloadDetect                      // POST /api/transfer/download/detect
    case downloadTask                        // POST /api/transfer/download/task
    case downloadTasks                       // GET  /api/transfer/download/tasks
    case downloadTaskStatus(id: String)      // GET  /api/transfer/download/task/{id}
    case downloadTaskDelete(id: String)      // DELETE /api/transfer/download/task/{id}
    case downloadHistoryClear                // DELETE /api/transfer/download/history

    // MARK: - Transfer/Upload 上传相关
    case uploadTask                          // POST /api/transfer/upload/task (multipart)
    case uploadTasks                         // GET  /api/transfer/upload/tasks
    case uploadTaskStatus(id: String)        // GET  /api/transfer/upload/task/{id}
    case uploadTaskDelete(id: String)        // DELETE /api/transfer/upload/task/{id}
    case uploadTasksClear                    // POST /api/transfer/upload/tasks/clear

    // MARK: - Preview 预览相关
    case previewFiles(folder: String)        // GET  /api/preview/files?folder=
    case previewThumbnail(path: String, size: Int) // GET /api/preview/thumbnail?path=&size=
    case previewContent(path: String)        // GET  /api/preview/content/{path}

    // MARK: - Browser 文件系统浏览
    case browserBrowse                       // POST /api/browser/browse
    case browserCreate                       // POST /api/browser/create

    // MARK: - Config 配置管理
    case configState                         // GET  /api/config/state
    case configSave                          // POST /api/config/save
    case configDownload                      // GET  /api/config/download
    case configDownloadSave                  // POST /api/config/download
    case configSources                       // GET  /api/config/sources
    case configSourcesAdd                    // POST /api/config/sources/add
    case configSourcesRemove                 // POST /api/config/sources/remove
    case configSourcesSwitch                 // POST /api/config/sources/switch
    case configCredentials(platform: String) // POST/DELETE /api/config/credentials/{platform}
    case configPresetLoad                    // POST /api/config/preset/load
    case configPresetSave                    // POST /api/config/preset/save
    case configPresetDelete                  // DELETE /api/config/preset/delete

    /// 获取端点路径
    var path: String {
        switch self {
        // Auth
        case .authVerify:
            return "/api/auth/verify"
        case .authCheck:
            return "/api/auth/check"

        // Global
        case .health:
            return "/api/health"
        case .config:
            return "/api/config"
        case .appConfig:
            return "/api/app"

        // File
        case .fileInfo(let folder):
            return "/api/file/info?folder=\(folder.urlEncoded)"
        case .fileRename:
            return "/api/file/rename"
        case .fileMove:
            return "/api/file/move"

        // Folder
        case .folderList(let sourceFolder):
            if let source = sourceFolder {
                return "/api/folder/list?source_folder=\(source.urlEncoded)"
            }
            return "/api/folder/list"
        case .folderCreate:
            return "/api/folder/create"
        case .folderReorder:
            return "/api/folder/reorder"
        case .folderOpen:
            return "/api/folder/open"

        // Download
        case .downloadDetect:
            return "/api/transfer/download/detect"
        case .downloadTask:
            return "/api/transfer/download/task"
        case .downloadTasks:
            return "/api/transfer/download/tasks"
        case .downloadTaskStatus(let id):
            return "/api/transfer/download/task/\(id)"
        case .downloadTaskDelete(let id):
            return "/api/transfer/download/task/\(id)"
        case .downloadHistoryClear:
            return "/api/transfer/download/history"

        // Upload
        case .uploadTask:
            return "/api/transfer/upload/task"
        case .uploadTasks:
            return "/api/transfer/upload/tasks"
        case .uploadTaskStatus(let id):
            return "/api/transfer/upload/task/\(id)"
        case .uploadTaskDelete(let id):
            return "/api/transfer/upload/task/\(id)"
        case .uploadTasksClear:
            return "/api/transfer/upload/tasks/clear"

        // Preview
        case .previewFiles(let folder):
            return "/api/preview/files?folder=\(folder.urlEncoded)"
        case .previewThumbnail(let path, let size):
            return "/api/preview/thumbnail?path=\(path.urlEncoded)&size=\(size)"
        case .previewContent(let path):
            return "/api/preview/content/\(path.urlEncoded)"

        // Browser
        case .browserBrowse:
            return "/api/browser/browse"
        case .browserCreate:
            return "/api/browser/create"

        // Config
        case .configState:
            return "/api/config/state"
        case .configSave:
            return "/api/config/save"
        case .configDownload:
            return "/api/config/download"
        case .configDownloadSave:
            return "/api/config/download"
        case .configSources:
            return "/api/config/sources"
        case .configSourcesAdd:
            return "/api/config/sources/add"
        case .configSourcesRemove:
            return "/api/config/sources/remove"
        case .configSourcesSwitch:
            return "/api/config/sources/switch"
        case .configCredentials(let platform):
            return "/api/config/credentials/\(platform)"
        case .configPresetLoad:
            return "/api/config/preset/load"
        case .configPresetSave:
            return "/api/config/preset/save"
        case .configPresetDelete:
            return "/api/config/preset/delete"
        }
    }

    /// 获取请求方法
    var method: HTTPMethod {
        switch self {
        // GET 请求
        case .authCheck, .health, .config, .appConfig,
             .fileInfo, .folderList,
             .downloadTasks, .downloadTaskStatus,
             .uploadTasks, .uploadTaskStatus,
             .previewFiles, .previewThumbnail, .previewContent,
             .configState, .configDownload, .configSources:
            return .GET

        // DELETE 请求
        case .downloadTaskDelete, .downloadHistoryClear,
             .uploadTaskDelete, .configPresetDelete:
            return .DELETE

        // POST 请求（默认）
        default:
            return .POST
        }
    }

    /// 是否需要认证（通过 API Key）
    var requiresAuth: Bool {
        switch self {
        case .health, .authVerify, .appConfig:
            return false
        default:
            return true
        }
    }
}

// MARK: - String URL 编码扩展
extension String {
    var urlEncoded: String {
        return self.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
