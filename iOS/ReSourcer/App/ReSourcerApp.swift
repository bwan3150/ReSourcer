//
//  ReSourcerApp.swift
//  ReSourcer
//
//  App 入口
//

import SwiftUI
import CryptoKit

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

    /// UITest：Share 上传路径（foreground multipart + background 会话 sharedContainer）
    @State private var e2eShareUploadProbeText: String = ""

    /// UITest：Share HEIC/视频原样上传探针
    @State private var e2eShareOriginalUploadProbeText: String = ""

    /// UITest：分享交接结果探针（server/source/unlock）
    @State private var e2eShareHandoffProbeText: String = ""

    /// Share 链接进入私密源时的手势解锁
    @State private var showSharePrivacyUnlock = false
    @State private var pendingShareHandoff: SharePendingDownloadHandoff?

    /// 从前台/后台切换时再消费一次 Share pending（扩展只拉起未带深链时的兜底）
    @Environment(\.scenePhase) private var scenePhase

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
                            runE2EShareUploadProbeIfNeeded()
                            runE2EShareOriginalUploadProbeIfNeeded()
                            runE2EHarnessIfNeeded(using: service)
                            Task { await consumePendingDownloadHandoffAsync() }
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
                    if !e2eShareUploadProbeText.isEmpty {
                        Text(e2eShareUploadProbeText)
                            .font(.system(size: 1))
                            .foregroundStyle(.clear)
                            .accessibilityIdentifier("e2eShareUploadProbe")
                            .accessibilityValue(e2eShareUploadProbeText)
                            .allowsHitTesting(false)
                    }
                    if !e2eShareOriginalUploadProbeText.isEmpty {
                        Text(e2eShareOriginalUploadProbeText)
                            .font(.system(size: 1))
                            .foregroundStyle(.clear)
                            .accessibilityIdentifier("e2eShareOriginalUploadProbe")
                            .accessibilityValue(e2eShareOriginalUploadProbeText)
                            .allowsHitTesting(false)
                    }
                    if !e2eShareHandoffProbeText.isEmpty {
                        Text(e2eShareHandoffProbeText)
                            .font(.system(size: 1))
                            .foregroundStyle(.clear)
                            .accessibilityIdentifier("e2eShareHandoffProbe")
                            .accessibilityValue(e2eShareHandoffProbeText)
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
            .overlay {
                if showSharePrivacyUnlock {
                    PatternLockView(
                        purpose: .verify,
                        onCancel: { handleSharePrivacyUnlockCancel() },
                        onSuccess: { handleSharePrivacyUnlockSuccess() }
                    )
                    .transition(.opacity)
                    .zIndex(1000)
                    .onAppear {
                        // UITest：九宫格绘制不稳定，用环境变量自动成功/取消
                        let auto = ProcessInfo.processInfo.environment["E2E_SHARE_PRIVACY_AUTO"] ?? ""
                        guard auto == "success" || auto == "cancel" else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            guard showSharePrivacyUnlock else { return }
                            if auto == "success" {
                                handleSharePrivacyUnlockSuccess()
                            } else {
                                handleSharePrivacyUnlockCancel()
                            }
                        }
                    }
                }
            }
            .withGlassAlerts()
            .preferredColorScheme(colorSchemeForPreference)
            .animation(AppTheme.Animation.standard, value: isLoggedIn)
            .onAppear {
                // E2E 播放偏好必须在预览打开前写入，且每次冷启动都覆盖上次测试残留
                applyE2EPlaybackPrefsIfNeeded()
                applyE2EPrivacySetupIfNeeded()
                themePreference = LocalStorageService.shared.getAppSettings().darkModePreference
                LocalStorageService.shared.syncServersToAppGroupIfNeeded()
                BackgroundUploadManager.shared.resumePendingFinalizations()
                checkExistingLogin()
                applyE2EPendingDownloadIfNeeded()
                Task { await consumePendingDownloadHandoffAsync() }
                runE2EShareSourcesProbeIfNeeded()
                runE2EShareUploadProbeIfNeeded()
                runE2EShareOriginalUploadProbeIfNeeded()
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
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await consumePendingDownloadHandoffAsync() }
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

    /// UITest：注入播放模式（避免点 Toggle 不稳定）
    /// `E2E_LIST_LOOP` / `E2E_SHUFFLE` / `E2E_SAME_TYPE` = `0`|`1`
    /// `E2E_ADVANCE_MODE` = `autoNext`|`repeatCurrent`（默认未注入时不改；连播跳图测需 autoNext）
    private func applyE2EPlaybackPrefsIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        let storage = LocalStorageService.shared
        if let v = env["E2E_LIST_LOOP"] {
            storage.saveListLoopEnabled(v == "1")
        }
        if let v = env["E2E_SHUFFLE"] {
            storage.saveShuffleEnabled(v == "1")
        }
        if let v = env["E2E_SAME_TYPE"] {
            var prefs = storage.getPreviewPreferences()
            prefs.filterAutoplayByFileType = (v == "1")
            _ = storage.savePreviewPreferences(prefs)
        }
        if let v = env["E2E_ADVANCE_MODE"], let mode = AdvanceMode(rawValue: v) {
            storage.saveAdvanceMode(mode)
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
        applyE2EPlaybackPrefsIfNeeded()
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

    /// UITest：覆盖 Share Extension 实际上传路径（小文件前台 multipart + background 会话 App Group）
    /// 用于回归 NSURLErrorDomain -995（BackgroundSessionRequiresSharedContainer）。
    private func runE2EShareUploadProbeIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        guard env["E2E_SHARE_UPLOAD_PROBE"] == "1" else { return }
        LocalStorageService.shared.syncServersToAppGroupIfNeeded()
        Task {
            let mainShared = BackgroundUploadSession.makeBackgroundConfiguration().sharedContainerIdentifier ?? ""
            let shareShared = BackgroundUploadManager.makeBackgroundConfiguration().sharedContainerIdentifier ?? ""
            let containerOK = AppGroup.containerURL != nil
            guard mainShared == AppGroup.identifier, shareShared == AppGroup.identifier, containerOK else {
                await MainActor.run {
                    e2eShareUploadProbeText =
                        "ERROR:sharedContainer main=\(mainShared) share=\(shareShared) container=\(containerOK)"
                }
                return
            }
            guard let server = ShareBridge.currentServer() else {
                await MainActor.run { e2eShareUploadProbeText = "ERROR:no-server" }
                return
            }
            do {
                let client = try ShareUploadClient(server: server)
                let sources = try await ShareUploadClient.loadSourceFoldersTryingCandidates(for: server)
                guard let target = sources.first else {
                    await MainActor.run { e2eShareUploadProbeText = "ERROR:no-source" }
                    return
                }
                // 1x1 PNG
                let png = Data(base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
                )!
                let name = "e2e-share-upload-\(Int(Date().timeIntervalSince1970)).png"
                let taskId = try await client.uploadDirect(
                    fileName: name,
                    data: png,
                    mimeType: "image/png",
                    to: target
                )
                await MainActor.run {
                    e2eShareUploadProbeText =
                        "OK:\(taskId)|shared=\(AppGroup.identifier)|file=\(name)|target=\(target)"
                }
            } catch {
                let ns = error as NSError
                await MainActor.run {
                    e2eShareUploadProbeText =
                        "ERROR:\(ns.domain) code=\(ns.code) \(error.localizedDescription)"
                }
            }
        }
    }

    /// UITest：注入分享链接交接（URL + 可选 serverId / sourceFolder）
    private func applyE2EPendingDownloadIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        guard let pending = env["E2E_PENDING_DOWNLOAD_URL"], !pending.isEmpty else { return }
        let serverId = env["E2E_SHARE_HANDOFF_SERVER_ID"]
        let source = env["E2E_SHARE_HANDOFF_SOURCE"]
        ShareBridge.setPendingDownload(
            SharePendingDownloadHandoff(
                url: pending,
                serverId: (serverId?.isEmpty == false) ? serverId : nil,
                sourceFolder: (source?.isEmpty == false) ? source : nil
            )
        )
    }

    /// UITest：标记私密源 / 写入手势图案（模拟已设置隐私）
    private func applyE2EPrivacySetupIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        if let path = env["E2E_PRIVATE_SOURCE_FOLDER"], !path.isEmpty {
            PrivacyManager.shared.setPrivate(path, true)
            PrivacyManager.shared.isUnlocked = false
        } else if let path = env["E2E_SHARE_HANDOFF_SOURCE"], !path.isEmpty {
            // 普通交接用例：清掉该源上可能残留的私密标记，避免串测
            PrivacyManager.shared.setPrivate(path, false)
        }
        if let pattern = env["E2E_PRIVACY_PATTERN"], !pattern.isEmpty {
            let dots = pattern.split(separator: "-").compactMap { Int($0) }
            if dots.count >= 4 {
                PrivacyManager.shared.setPattern(dots)
            }
        }
        if env["E2E_PRIVACY_UNLOCKED"] == "1" {
            PrivacyManager.shared.isUnlocked = true
        }
    }

    private func handleOpenURL(_ url: URL) {
        if E2EHarness.handleNowPlayingDeepLink(url) {
            return
        }
        if let handoff = ShareBridge.parseDownloadDeepLink(url) {
            ShareBridge.setPendingDownload(handoff)
            Task { await consumePendingDownloadHandoffAsync() }
        }
    }

    /// Share 链接交接：切服务器 / 源文件夹；私密源先手势解锁
    @MainActor
    private func consumePendingDownloadHandoffAsync() async {
        guard let handoff = ShareBridge.peekPendingDownload() else { return }
        guard isLoggedIn, apiService != nil else { return }

        // 1) 切换服务器（若指定且不同）
        if let serverId = handoff.serverId, !serverId.isEmpty,
           LocalStorageService.shared.getCurrentServerId() != serverId,
           let server = LocalStorageService.shared.getServer(by: serverId),
           let service = APIService.create(for: server) {
            _ = LocalStorageService.shared.setCurrentServer(serverId)
            apiService = service
        }

        guard let service = apiService else { return }

        // 2) 私密源且未解锁 → 弹出图案锁，暂不消费 pending
        if let source = handoff.sourceFolder, !source.isEmpty,
           PrivacyManager.shared.isPrivate(source),
           !PrivacyManager.shared.isUnlocked {
            // 尚未设置图案时无法校验：安全起见取消交接
            guard PrivacyManager.shared.hasPattern else {
                ShareBridge.clearPendingDownload()
                e2eShareHandoffProbeText = "CANCELLED:no-pattern|\(source)"
                return
            }
            pendingShareHandoff = handoff
            showSharePrivacyUnlock = true
            e2eShareHandoffProbeText = "WAITING_UNLOCK:\(source)"
            return
        }

        await finishShareHandoff(handoff, using: service)
    }

    @MainActor
    private func finishShareHandoff(_ handoff: SharePendingDownloadHandoff, using service: APIService) async {
        // 确保 pending URL 仍在（DownloadView 会 consume）
        ShareBridge.setPendingDownload(handoff)

        if let source = handoff.sourceFolder, !source.isEmpty {
            do {
                try await service.config.switchSourceFolder(to: source)
                NavigationState.shared.setSourceFolder(source)
                NotificationCenter.default.post(name: .sourceFolderDidChange, object: nil)
            } catch {
                e2eShareHandoffProbeText =
                    "ERROR:switch-source \(error.localizedDescription)"
                // 仍尝试进入下载预填（用户可看到链接），但不谎称源已切换
            }
        }

        let currentId = LocalStorageService.shared.getCurrentServerId() ?? ""
        let sourceNow = handoff.sourceFolder ?? NavigationState.shared.sourceFolder
        e2eShareHandoffProbeText = "OK:\(currentId)|\(sourceNow)|\(handoff.url)"

        selectedTab = .download
        NotificationCenter.default.post(name: .shareDownloadPrefillRequested, object: nil)
    }

    @MainActor
    private func handleSharePrivacyUnlockSuccess() {
        showSharePrivacyUnlock = false
        PrivacyManager.shared.isUnlocked = true
        guard let handoff = pendingShareHandoff else { return }
        pendingShareHandoff = nil
        Task {
            guard let service = apiService else { return }
            await finishShareHandoff(handoff, using: service)
        }
    }

    @MainActor
    private func handleSharePrivacyUnlockCancel() {
        showSharePrivacyUnlock = false
        let source = pendingShareHandoff?.sourceFolder ?? ""
        pendingShareHandoff = nil
        // 取消：清空 pending，不切换到私密源，不进入该源的下载预填流
        ShareBridge.clearPendingDownload()
        e2eShareHandoffProbeText = "CANCELLED:unlock|\(source)"
    }

    /// UITest：沿 Share 上传客户端直传真实 HEIC / MOV，校验魔数与哈希（原样字节）
    private func runE2EShareOriginalUploadProbeIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        guard env["E2E_SHARE_ORIGINAL_UPLOAD_PROBE"] == "1" else { return }
        LocalStorageService.shared.syncServersToAppGroupIfNeeded()
        Task {
            guard let server = ShareBridge.currentServer() else {
                await MainActor.run { e2eShareOriginalUploadProbeText = "ERROR:no-server" }
                return
            }
            do {
                let client = try ShareUploadClient(server: server)
                let sources = try await ShareUploadClient.loadSourceFoldersTryingCandidates(for: server)
                guard let target = sources.first else {
                    await MainActor.run { e2eShareOriginalUploadProbeText = "ERROR:no-source" }
                    return
                }

                let heicPath = env["E2E_HEIC_SAMPLE_PATH"]
                    ?? Bundle.main.path(forResource: "tiled_heic_c007", ofType: "heic")
                let movPath = env["E2E_MOV_SAMPLE_PATH"]

                var parts: [String] = []

                if let heicPath, let heicData = try? Data(contentsOf: URL(fileURLWithPath: heicPath)) {
                    let name = "e2e-share-orig-\(Int(Date().timeIntervalSince1970)).heic"
                    let hash = Self.sha256Hex(heicData)
                    _ = try await client.uploadDirect(
                        fileName: name,
                        data: heicData,
                        mimeType: "image/heic",
                        to: target
                    )
                    let stored = URL(fileURLWithPath: target).appendingPathComponent(name)
                    // 上传任务异步落盘；轮询短暂等待
                    var matched = false
                    var storedHash = ""
                    var magic = ""
                    for _ in 0..<40 {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        if let storedData = try? Data(contentsOf: stored) {
                            storedHash = Self.sha256Hex(storedData)
                            magic = Self.bmffBrand(storedData) ?? "unknown"
                            matched = (storedHash == hash)
                            if matched { break }
                        }
                    }
                    parts.append(
                        "HEIC:\(matched ? "OK" : "FAIL")|ext=heic|magic=\(magic)|hash=\(hash)|stored=\(storedHash)|file=\(name)"
                    )
                } else {
                    parts.append("HEIC:SKIP:no-sample")
                }

                if let movPath, let movData = try? Data(contentsOf: URL(fileURLWithPath: movPath)) {
                    let name = "e2e-share-orig-\(Int(Date().timeIntervalSince1970)).mov"
                    let hash = Self.sha256Hex(movData)
                    _ = try await client.uploadDirect(
                        fileName: name,
                        data: movData,
                        mimeType: "video/quicktime",
                        to: target
                    )
                    let stored = URL(fileURLWithPath: target).appendingPathComponent(name)
                    var matched = false
                    var storedHash = ""
                    var magic = ""
                    for _ in 0..<40 {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        if let storedData = try? Data(contentsOf: stored) {
                            storedHash = Self.sha256Hex(storedData)
                            magic = Self.bmffBrand(storedData) ?? "unknown"
                            matched = (storedHash == hash)
                            if matched { break }
                        }
                    }
                    parts.append(
                        "MOV:\(matched ? "OK" : "FAIL")|ext=mov|magic=\(magic)|hash=\(hash)|stored=\(storedHash)|file=\(name)"
                    )
                } else {
                    parts.append("MOV:SKIP:no-sample")
                }

                await MainActor.run {
                    e2eShareOriginalUploadProbeText = parts.joined(separator: ";")
                }
            } catch {
                await MainActor.run {
                    e2eShareOriginalUploadProbeText = "ERROR:\(error.localizedDescription)"
                }
            }
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// ISO BMFF `ftyp` brand（HEIC/MOV/MP4）
    private static func bmffBrand(_ data: Data) -> String? {
        guard data.count >= 12 else { return nil }
        let ftyp = data.subdata(in: 4..<8)
        guard String(data: ftyp, encoding: .ascii) == "ftyp" else { return nil }
        return String(data: data.subdata(in: 8..<12), encoding: .ascii)
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
