//
//  APIServiceUsageExamples.swift
//  ReSourcer
//
//  API 服务使用示例 - 展示如何调用各个 API
//  注意：此文件仅作为参考文档，实际使用时可删除
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 使用示例

/// API 服务使用示例类
/// 展示如何在 SwiftUI/UIKit 中使用各个 API 服务
enum APIServiceUsageExamples {

    // MARK: - 1. 初始化和连接

    /// 示例：创建服务器配置并连接
    static func exampleConnect() async {
        // 创建服务器配置
        let server = Server(
            name: "我的服务器",
            baseURL: "http://192.168.1.100:1234",
            apiKey: "your-api-key-here"
        )

        // 创建 API 服务
        guard let apiService = await APIService.create(for: server) else {
            print("无效的服务器 URL")
            return
        }

        // 检查连接状态
        let status = await apiService.checkConnection()
        switch status {
        case .online:
            print("服务器在线")
        case .authError:
            print("API Key 无效")
        case .offline:
            print("服务器离线")
        case .checking:
            print("正在检查...")
        }
    }

    // MARK: - 2. 文件操作

    /// 示例：获取文件列表并移动文件
    static func exampleFileOperations(apiService: APIService) async {
        do {
            // 获取文件列表
            let files = try await apiService.file.getFiles(in: "/path/to/source/folder")
            print("找到 \(files.count) 个文件")

            // 遍历文件
            for file in files {
                print("文件: \(file.name), 类型: \(file.fileType), 大小: \(file.formattedSize)")

                if file.isVideo, let duration = file.formattedDuration {
                    print("  视频时长: \(duration)")
                }
            }

            // 移动文件到分类文件夹
            if let firstFile = files.first {
                let newPath = try await apiService.file.moveFile(
                    at: firstFile.path,
                    to: "/path/to/target/category"
                )
                print("文件已移动到: \(newPath)")
            }

            // 重命名文件
            if let file = files.first {
                let newPath = try await apiService.file.renameFile(
                    at: file.path,
                    to: "new_name.jpg"
                )
                print("文件已重命名，新路径: \(newPath)")
            }
        } catch {
            print("文件操作失败: \(error)")
        }
    }

    // MARK: - 3. 文件夹操作

    /// 示例：管理文件夹
    static func exampleFolderOperations(apiService: APIService) async {
        do {
            // 获取 Gallery 文件夹列表
            let folders = try await apiService.folder.getGalleryFolders()
            for folder in folders {
                print("文件夹: \(folder.name), 文件数: \(folder.fileCount), 是源文件夹: \(folder.isSource)")
            }

            // 获取子文件夹列表
            let subfolders = try await apiService.folder.getSubfolders(in: "/path/to/source")
            for folder in subfolders {
                print("子文件夹: \(folder.name), 隐藏: \(folder.hidden)")
            }

            // 创建新分类文件夹
            let newFolder = try await apiService.folder.createFolder(name: "新分类")
            print("已创建文件夹: \(newFolder)")

            // 保存子文件夹排序
            try await apiService.folder.saveFolderOrder(
                folderPath: "/path/to/source",
                order: ["分类A", "分类B", "分类C"]
            )
        } catch {
            print("文件夹操作失败: \(error)")
        }
    }

    // MARK: - 4. 下载任务

    /// 示例：URL 检测和下载管理
    static func exampleDownloadOperations(apiService: APIService) async {
        do {
            // 检测 URL
            let url = "https://www.youtube.com/watch?v=example"
            let detectResult = try await apiService.download.detectUrl(url)
            print("平台: \(detectResult.platformName)")
            print("下载器: \(detectResult.downloader.displayName)")
            print("需要认证: \(detectResult.requiresAuth)")

            // 创建下载任务
            let taskId = try await apiService.download.createTask(
                url: url,
                saveFolder: "/path/to/downloads"
            )
            print("已创建下载任务: \(taskId)")

            // 获取所有任务
            let tasks = try await apiService.download.getTasks()
            for task in tasks {
                print("任务: \(task.id), 状态: \(task.status), 进度: \(task.progressText)")
                if let fileName = task.fileName {
                    print("  文件名: \(fileName)")
                }
            }

            // 获取活跃任务
            let activeTasks = try await apiService.download.getActiveTasks()
            print("正在进行的任务数: \(activeTasks.count)")

            // 取消任务
            if let task = activeTasks.first {
                try await apiService.download.deleteTask(id: task.id)
                print("已取消任务: \(task.id)")
            }

            // 清空历史
            try await apiService.download.clearHistory()
        } catch {
            print("下载操作失败: \(error)")
        }
    }

    // MARK: - 5. 上传文件

    /// 示例：上传文件
    static func exampleUploadOperations(apiService: APIService) async {
        do {
            // 准备上传文件
            let imageData = Data() // 实际应用中从 UIImage 或文件获取
            let file = PendingUploadFile(
                fileName: "photo.jpg",
                data: imageData,
                mimeType: "image/jpeg"
            )

            // 上传文件
            let taskIds = try await apiService.upload.uploadFiles(
                [file],
                to: "/path/to/upload/folder"
            )
            print("已创建上传任务: \(taskIds)")

            // 获取上传任务状态
            let tasks = try await apiService.upload.getTasks()
            for task in tasks {
                print("上传: \(task.fileName), 进度: \(task.progressDescription)")
            }

            // 清除已完成的任务
            let clearedCount = try await apiService.upload.clearCompletedTasks()
            print("已清除 \(clearedCount) 个任务")
        } catch {
            print("上传操作失败: \(error)")
        }
    }

    // MARK: - 6. 预览和缩略图

    /// 示例：获取预览和缩略图
    static func examplePreviewOperations(apiService: APIService) async {
        do {
            // 获取文件列表
            let files = try await apiService.preview.getFiles(in: "/path/to/folder")

            // 获取缩略图数据
            if let file = files.first {
                let thumbnailData = try await apiService.preview.getThumbnail(
                    for: file.path,
                    size: 300
                )
                print("缩略图大小: \(thumbnailData.count) 字节")

                #if canImport(UIKit)
                // 转换为 UIImage
                if let image = try await apiService.preview.getThumbnailImage(for: file.path) {
                    print("图片尺寸: \(image.size)")
                }
                #endif
            }

            // 获取缩略图 URL（用于 AsyncImage 等）
            if let file = files.first {
                if let thumbnailURL = await apiService.preview.getThumbnailURL(
                    for: file.path,
                    size: 300,
                    baseURL: apiService.baseURL,
                    apiKey: apiService.apiKey
                ) {
                    print("缩略图 URL: \(thumbnailURL)")
                }
            }

            // 获取文件内容 URL（用于视频播放）
            if let videoFile = files.first(where: { $0.isVideo }) {
                if let contentURL = await apiService.preview.getContentURL(
                    for: videoFile.path,
                    baseURL: apiService.baseURL,
                    apiKey: apiService.apiKey
                ) {
                    print("视频 URL: \(contentURL)")
                    // 可以用于 AVPlayer 播放
                }
            }
        } catch {
            print("预览操作失败: \(error)")
        }
    }

    // MARK: - 7. 文件系统浏览

    /// 示例：浏览文件系统
    static func exampleBrowserOperations(apiService: APIService) async {
        do {
            // 从主目录开始浏览
            let homeResponse = try await apiService.browser.browseHome()
            print("当前路径: \(homeResponse.currentPath)")
            print("父路径: \(homeResponse.parentPath ?? "无")")

            for item in homeResponse.items {
                let type = item.isDirectory ? "目录" : "文件"
                print("  [\(type)] \(item.name)")
            }

            // 浏览指定目录
            let response = try await apiService.browser.browse(path: "/Users/username/Downloads")
            print("目录项数量: \(response.items.count)")

            // 仅获取子目录
            let subdirs = try await apiService.browser.getSubdirectories(in: "/Users/username")
            print("子目录数: \(subdirs.count)")

            // 创建新目录
            let newPath = try await apiService.browser.createDirectory(
                in: "/Users/username/Documents",
                name: "新文件夹"
            )
            print("已创建目录: \(newPath)")
        } catch {
            print("浏览操作失败: \(error)")
        }
    }

    // MARK: - 8. 配置管理

    /// 示例：管理配置
    static func exampleConfigOperations(apiService: APIService) async {
        do {
            // 获取配置状态
            let state = try await apiService.config.getConfigState()
            print("源文件夹: \(state.sourceFolder)")
            print("隐藏文件夹: \(state.hiddenFolders)")
            print("预设数量: \(state.presets.count)")

            // 获取下载器配置
            let downloadConfig = try await apiService.config.getDownloadConfig()
            print("yt-dlp 版本: \(downloadConfig.ytdlpVersion)")
            print("X 认证状态: \(downloadConfig.authStatus.x ? "已配置" : "未配置")")
            print("Pixiv 认证状态: \(downloadConfig.authStatus.pixiv ? "已配置" : "未配置")")

            // 源文件夹管理
            let sources = try await apiService.config.getSourceFolders()
            print("当前源文件夹: \(sources.current)")
            print("备用源文件夹: \(sources.backups)")

            // 切换源文件夹
            if let backup = sources.backups.first {
                try await apiService.config.switchSourceFolder(to: backup)
                print("已切换到: \(backup)")
            }

            // 上传认证信息
            let cookies = "# Netscape HTTP Cookie File\n..."
            try await apiService.config.uploadCredentials(platform: .x, content: cookies)
            print("X cookies 已上传")

            // 加载预设
            if let preset = state.presets.first {
                let response = try await apiService.config.loadPreset(name: preset.name)
                print("已加载预设: \(response.presetName)")
                print("分类: \(response.categories)")
            }
        } catch {
            print("配置操作失败: \(error)")
        }
    }

    // MARK: - 9. 本地存储

    /// 示例：使用本地存储服务
    static func exampleLocalStorage() {
        let storage = LocalStorageService.shared

        // 添加服务器
        let server = Server(
            name: "家庭服务器",
            baseURL: "http://192.168.1.100:1234",
            apiKey: "my-api-key"
        )
        storage.addServer(server)

        // 设置为当前服务器
        storage.setCurrentServer(server.id)
        storage.setLoggedIn(true)

        // 获取所有服务器
        let servers = storage.getServers()
        print("已保存 \(servers.count) 个服务器")

        // 获取当前服务器
        if let current = storage.getCurrentServer() {
            print("当前服务器: \(current.name)")
        }

        // 应用设置
        var settings = storage.getAppSettings()
        settings.thumbnailSize = 400
        settings.darkModePreference = .dark
        storage.saveAppSettings(settings)

        // 检查登录状态
        if storage.isLoggedIn() {
            print("用户已登录")
        }
    }
}

// MARK: - SwiftUI 集成示例

/*
 在 SwiftUI 中使用 APIService 的示例：

 ```swift
 import SwiftUI

 struct ContentView: View {
     @StateObject private var viewModel = ContentViewModel()

     var body: some View {
         List(viewModel.files) { file in
             HStack {
                 AsyncImage(url: viewModel.thumbnailURL(for: file)) { image in
                     image.resizable()
                 } placeholder: {
                     ProgressView()
                 }
                 .frame(width: 50, height: 50)

                 VStack(alignment: .leading) {
                     Text(file.name)
                     Text(file.formattedSize)
                         .font(.caption)
                         .foregroundColor(.secondary)
                 }
             }
         }
         .task {
             await viewModel.loadFiles()
         }
     }
 }

 @MainActor
 class ContentViewModel: ObservableObject {
     @Published var files: [FileInfo] = []

     private var apiService: APIService?

     init() {
         if let server = LocalStorageService.shared.getCurrentServer() {
             apiService = APIService.create(for: server)
         }
     }

     func loadFiles() async {
         guard let api = apiService else { return }
         do {
             files = try await api.file.getFiles(in: "/path/to/folder")
         } catch {
             print("加载失败: \(error)")
         }
     }

     func thumbnailURL(for file: FileInfo) -> URL? {
         guard let api = apiService else { return nil }
         return api.preview.getThumbnailURL(
             for: file.path,
             baseURL: api.baseURL,
             apiKey: api.apiKey
         )
     }
 }
 ```
*/
