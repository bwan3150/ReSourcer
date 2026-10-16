//
//  ReSourcerApp.swift
//  ReSourcer
//
//  App 入口
//

import SwiftUI

@main
struct ReSourcerApp: App {

    // MARK: - State

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// 当前选中的 Tab
    @State private var selectedTab: AppTab = .gallery

    /// 是否已登录（连接到服务器）
    @State private var isLoggedIn = false

    /// 当前 API 服务
    @State private var apiService: APIService?

    /// 主题偏好
    @State private var themePreference: LocalStorageService.AppSettings.DarkModePreference = .system

    /// UITest：Share Extension 同源文件夹探测结果（App Group + Keychain + 真实 API）
    @State private var e2eShareSourcesProbeText: String = ""

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoggedIn, let service = apiService {
                    // 主界面
                    MainTabView(selectedTab: $selectedTab, apiService: service)
                } else {
                    // 登录/连接界面
                    ServerConnectView(
                        onConnected: { service in
                            self.apiService = service
                            self.isLoggedIn = true
                            LocalStorageService.shared.syncServersToAppGroupIfNeeded()
                            Self.resumeBackgroundUploadsIfAppropriate(using: service)
                            runE2EShareSourcesProbeIfNeeded()
                            runE2EHarnessIfNeeded(using: service)
                        }
                    )
                }
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    if !e2eShareSourcesProbeText.isEmpty {
                        Text(e2eShareSourcesProbeText)
                            .font(.system(size: 1))
                            .foregroundStyle(.clear)
                            .accessibilityIdentifier("e2eShareSourcesProbe")
                            .accessibilityValue(e2eShareSourcesProbeText)
                            .allowsHitTesting(false)
                    }
                    let env = ProcessInfo.processInfo.environment
                    let np = env["E2E_NOWPLAYING_PROBE"] == "1"
                    let up = env["E2E_KILL_UPLOAD"] == "1" || env["E2E_UPLOAD_RESUME_CHECK"] == "1"
                    if np || up {
                        E2EProbeOverlay(
                            showNowPlaying: np,
                            showUpload: up,
                            showRemoteButtons: np
                        )
                    }
                }
            }
            .withGlassAlerts()
            .preferredColorScheme(colorSchemeForPreference)
            .animation(AppTheme.Animation.standard, value: isLoggedIn)
            .onAppear {
                themePreference = LocalStorageService.shared.getAppSettings().darkModePreference
                LocalStorageService.shared.syncServersToAppGroupIfNeeded()
                BackgroundUploadManager.shared.resumePendingFinalizations()
                checkExistingLogin()
                applyE2EPendingDownloadIfNeeded()
                consumePendingDownloadHandoff()
                runE2EShareSourcesProbeIfNeeded()
                if let service = apiService {
                    runE2EHarnessIfNeeded(using: service)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
                themePreference = LocalStorageService.shared.getAppSettings().darkModePreference
            }
            .onReceive(NotificationCenter.default.publisher(for: .userDidLogout)) { _ in
                handleLogout()
            }
            .onReceive(NotificationCenter.default.publisher(for: .shareDownloadPrefillRequested)) { _ in
                selectedTab = .download
            }
            .onOpenURL { url in
                handleOpenURL(url)
            }
        }
    }

    // MARK: - Theme

    /// 将用户偏好转换为 ColorScheme
    private var colorSchemeForPreference: ColorScheme? {
        switch themePreference {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    // MARK: - Methods

    /// 检查是否已有登录状态
    private func checkExistingLogin() {
        // UITest / E2E：通过环境变量注入服务器与 Key，跳过手动登录
        if applyE2ELoginIfNeeded() {
            return
        }

        if LocalStorageService.shared.isLoggedIn(),
           let server = LocalStorageService.shared.getCurrentServer(),
           let service = APIService.create(for: server) {
            self.apiService = service
            self.isLoggedIn = true
            Self.resumeBackgroundUploadsIfAppropriate(using: service)

            // 快速探测当前地址，不可达则弹切换对话框；仅检查 auth 失效时登出
            Task {
                await service.probeConnectivity()

                let status = await service.checkConnection()
                if status == .authError {
                    await MainActor.run {
                        handleLogout()
                        GlassAlertManager.shared.showError("认证失败", message: "API Key 已失效，请重新登录")
                    }
                }
            }
        }
    }

    /// 恢复杀进程前未完成的分片上传（background URLSession 同 identifier 重连）
    private static func resumeBackgroundUploads(using service: APIService) {
        Task {
            let finished = await service.upload.resumePendingChunkJobs()
            if !finished.isEmpty {
                await MainActor.run {
                    GlassAlertManager.shared.showSuccess(
                        "后台上传已恢复",
                        message: "完成 \(finished.count) 个未完成的分片任务"
                    )
                }
            }
        }
    }

    /// E2E 杀进程续传由探针接管 resume，避免与自动恢复竞态
    private static func resumeBackgroundUploadsIfAppropriate(using service: APIService) {
        let env = ProcessInfo.processInfo.environment
        if env["E2E_KILL_UPLOAD"] == "1" || env["E2E_UPLOAD_RESUME_CHECK"] == "1" {
            return
        }
        resumeBackgroundUploads(using: service)
    }

    private func runE2EHarnessIfNeeded(using service: APIService) {
        let env = ProcessInfo.processInfo.environment
        if env["E2E_NOWPLAYING_PROBE"] == "1" {
            E2EHarness.shared.startNowPlayingProbeIfNeeded()
        }
        if env["E2E_KILL_UPLOAD"] == "1" {
            E2EHarness.shared.startKillUploadIfNeeded(apiService: service)
        }
        if env["E2E_UPLOAD_RESUME_CHECK"] == "1" {
            E2EHarness.shared.checkUploadResumeIfNeeded(apiService: service)
        }
    }

    /// 读取 `E2E_SERVER_URL` / `E2E_API_KEY`（由 XCUITest launchEnvironment 注入）
    @discardableResult
    private func applyE2ELoginIfNeeded() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["E2E_SERVER_URL"], !url.isEmpty,
              let key = env["E2E_API_KEY"], !key.isEmpty else {
            return false
        }
        var server: Server
        if let existing = LocalStorageService.shared.getServers().first(where: { $0.baseURL == url }) {
            server = existing.with(name: "E2E", apiKey: key)
            _ = LocalStorageService.shared.updateServer(server)
        } else {
            server = Server(name: "E2E", baseURL: url, apiKey: key)
            _ = LocalStorageService.shared.addServer(server)
        }
        _ = LocalStorageService.shared.setCurrentServer(server.id)
        LocalStorageService.shared.saveActiveURL(url, forServerId: server.id)
        LocalStorageService.shared.setLoggedIn(true)
        LocalStorageService.shared.syncServersToAppGroupIfNeeded()
        guard let service = APIService.create(for: server) else { return false }
        self.apiService = service
        self.isLoggedIn = true
        Self.resumeBackgroundUploadsIfAppropriate(using: service)
        return true
    }

    /// UITest：沿 Share Extension 路径（App Group 服务器 + Keychain apiKey + 活跃 URL）拉真实源文件夹
    private func runE2EShareSourcesProbeIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        guard env["E2E_SHARE_SOURCES_PROBE"] == "1" else { return }
        LocalStorageService.shared.syncServersToAppGroupIfNeeded()
        Task {
            guard let server = ShareBridge.currentServer() else {
                await MainActor.run { e2eShareSourcesProbeText = "ERROR:no-server" }
                return
            }
            if server.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { e2eShareSourcesProbeText = "ERROR:empty-api-key" }
                return
            }
            let label = ShareBridge.sharePickerLabel(for: server)
            do {
                let paths = try await ShareUploadClient.loadSourceFoldersTryingCandidates(for: server)
                let active = ShareBridge.effectiveBaseURL(for: server)
                let payload = "OK:\(paths.count)|\(active)|\(label)|\(paths.joined(separator: ","))"
                await MainActor.run { e2eShareSourcesProbeText = payload }
            } catch {
                await MainActor.run {
                    e2eShareSourcesProbeText = "ERROR:\(error.localizedDescription)"
                }
            }
        }
    }

    /// UITest：`E2E_PENDING_DOWNLOAD_URL` 注入待预填链接（模拟 Share Extension 交接）
    private func applyE2EPendingDownloadIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        if let pending = env["E2E_PENDING_DOWNLOAD_URL"], !pending.isEmpty {
            ShareBridge.setPendingDownloadURL(pending)
        }
    }

    private func handleOpenURL(_ url: URL) {
        if E2EHarness.handleNowPlayingDeepLink(url) {
            return
        }
        if let pending = ShareBridge.parseDownloadDeepLink(url) {
            ShareBridge.setPendingDownloadURL(pending)
            consumePendingDownloadHandoff()
        }
    }

    /// 切到下载 Tab，并通知 DownloadView 预填（不自动 detect / 不自动下载）
    private func consumePendingDownloadHandoff() {
        guard ShareBridge.peekPendingDownloadURL() != nil else { return }
        selectedTab = .download
        NotificationCenter.default.post(name: .shareDownloadPrefillRequested, object: nil)
    }

    /// 处理登出
    private func handleLogout() {
        withAnimation(AppTheme.Animation.standard) {
            isLoggedIn = false
            apiService = nil
            selectedTab = .gallery
        }
    }

}

// MARK: - Notifications

extension Notification.Name {
    /// Share Extension / 深链要求预填下载 URL（仅预填，不自动下载）
    static let shareDownloadPrefillRequested = Notification.Name("shareDownloadPrefillRequested")
}

// MARK: - App Tab 枚举

/// 主要 Tab 项
enum AppTab: String, GlassTabItem, CaseIterable {
    case gallery
    case classifier
    case download
    case settings

    var title: String {
        switch self {
        case .gallery: return "首页"
        case .classifier: return "分类"
        case .download: return "下载"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .gallery: return "photo.on.rectangle"
        case .classifier: return "square.grid.2x2"
        case .download: return "arrow.down.circle"
        case .settings: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .gallery: return "photo.on.rectangle.fill"
        case .classifier: return "square.grid.2x2.fill"
        case .download: return "arrow.down.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
