//
//  APIService.swift
//  ReSourcer
//
//  主 API 服务入口 - 聚合所有子服务
//

import Foundation

/// API 服务 - 提供对所有后端 API 的统一访问入口
@MainActor
final class APIService: ObservableObject {

    // MARK: - Properties

    /// 当前连接的服务器
    let server: Server

    /// 网络管理器
    private let networkManager: NetworkManager

    // MARK: - Sub Services

    /// 认证服务
    let auth: AuthService

    /// 文件操作服务
    let file: FileService

    /// 文件夹操作服务
    let folder: FolderService

    /// 下载服务
    let download: DownloadService

    /// 上传服务
    let upload: UploadService

    /// 预览服务
    let preview: PreviewService

    /// 文件系统浏览服务
    let browser: BrowserService

    /// 配置服务
    let config: ConfigService

    // MARK: - Initialization

    /// 初始化 API 服务
    /// - Parameter server: 服务器配置
    init(server: Server) {
        guard let baseURL = server.url else {
            fatalError("Invalid server URL: \(server.baseURL)")
        }

        self.server = server
        self.networkManager = NetworkManager(
            baseURL: baseURL,
            apiKey: server.apiKey,
            timeoutInterval: 30
        )

        // 初始化所有子服务
        self.auth = AuthService(networkManager: networkManager)
        self.file = FileService(networkManager: networkManager)
        self.folder = FolderService(networkManager: networkManager)
        self.download = DownloadService(networkManager: networkManager)
        self.upload = UploadService(networkManager: networkManager)
        self.preview = PreviewService(networkManager: networkManager)
        self.browser = BrowserService(networkManager: networkManager)
        self.config = ConfigService(networkManager: networkManager)
    }

    // MARK: - Convenience Methods

    /// 获取服务器基础 URL
    var baseURL: URL {
        server.url!
    }

    /// 获取 API Key
    var apiKey: String {
        server.apiKey
    }

    /// 检查服务器连接状态
    /// - Returns: 服务器状态
    func checkConnection() async -> ServerStatus {
        do {
            // 首先检查健康状态
            _ = try await auth.checkHealth()

            // 然后验证 API Key
            let isValid = try await auth.checkAuth()
            return isValid ? .online : .authError
        } catch let error as APIError {
            switch error {
            case .unauthorized:
                return .authError
            default:
                return .offline
            }
        } catch {
            return .offline
        }
    }

    /// 验证 API Key
    /// - Parameter apiKey: 要验证的 API Key
    /// - Returns: 是否有效
    func verifyApiKey(_ apiKey: String) async -> Bool {
        do {
            return try await auth.verifyApiKey(apiKey)
        } catch {
            return false
        }
    }
}

// MARK: - Static Factory Methods

extension APIService {

    /// 创建 API 服务实例（静态工厂方法）
    /// - Parameter server: 服务器配置
    /// - Returns: API 服务实例，如果 URL 无效则返回 nil
    static func create(for server: Server) -> APIService? {
        guard server.url != nil else {
            return nil
        }
        return APIService(server: server)
    }

    /// 测试服务器连接
    /// - Parameters:
    ///   - baseURL: 服务器基础 URL
    ///   - apiKey: API Key
    /// - Returns: 连接结果（成功/失败原因）
    static func testConnection(baseURL: String, apiKey: String) async -> Result<Void, APIError> {
        guard URL(string: baseURL) != nil else {
            return .failure(.invalidURL)
        }

        let tempServer = Server(name: "Test", baseURL: baseURL, apiKey: apiKey)
        guard let apiService = APIService.create(for: tempServer) else {
            return .failure(.invalidURL)
        }

        let status = await apiService.checkConnection()
        switch status {
        case .online:
            return .success(())
        case .authError:
            return .failure(.unauthorized)
        case .offline:
            return .failure(.networkError(URLError(.notConnectedToInternet)))
        case .checking:
            return .failure(.unknown("连接检查超时"))
        }
    }
}
