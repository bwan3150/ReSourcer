//
//  SettingsView.swift
//  ReSourcer
//
//  设置页面
//

import SwiftUI

struct SettingsView: View {

    // MARK: - Properties

    let apiService: APIService

    // 服务器健康状态
    @State private var healthStatus: ServerStatus = .checking
    @State private var appConfig: AppConfigResponse?

    // 地址切换
    @State private var showAddressList = false
    @State private var isSwitchingURL = false

    // 源文件夹
    @State private var sourceFolders: SourceFoldersResponse?
    @State private var showSourceFolderList = false

    // 语言设置
    @State private var language: LocalStorageService.AppSettings.Language = .zh

    // 主题设置
    @State private var themePreference: LocalStorageService.AppSettings.DarkModePreference = .system

    // 缓存大小
    @State private var totalCacheSize: String = ""

    // 断开连接
    @State private var showDisconnectConfirm = false

    // 重新索引进度
    @State private var isReindexing = false

    // 检查更新
    @State private var isCheckingUpdate = false
    @State private var latestServerVersion: String?
    @State private var latestIOSVersion: String?
    @State private var isUpdatingServer = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    // 1. 服务器状态
                    serverSection

                    // 2. 源文件夹
                    sourceFolderSection

                    // 3. 语言切换
                    languageSection

                    // 4. 主题切换
                    themeSection

                    // 5. 偏好设置
                    preferencesSection

                    // 6. 认证
                    authSection

                    // 7. 下载器
                    downloaderSection

                    // 8. 缓存管理
                    cacheSection

                    // 8. 关于
                    aboutSection

                    // 9. 断开连接
                    disconnectSection

                    // 10. 版本信息
                    versionFooter
                }
                .padding(AppTheme.Spacing.lg)
            }
            .navigationTitle("设置")
        }
        .task {
            await loadSettings()
        }
        .glassExitConfirm(
            isPresented: $showDisconnectConfirm,
            title: "断开连接？",
            message: "将退出当前服务器，可以重新连接"
        ) {
            disconnect()
        }
        .overlay {
            if isReindexing {
                reindexProgressOverlay
            }
        }
    }

    // MARK: - 重新索引进度弹窗

    private var reindexProgressOverlay: some View {
        ZStack {
            // 背景遮罩，拦截所有触摸
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            // 弹窗卡片
            VStack(spacing: AppTheme.Spacing.xl) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(.white)

                Text("正在重新索引")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(AppTheme.Spacing.xxxl)
            .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
        }
    }

    // MARK: - 1. 服务器状态

    private var serverSection: some View {
        SettingsSection(title: "服务器") {
            VStack(spacing: 0) {
                // 服务器信息行（可点击展开地址列表）
                Button {
                    // 仅在有备用地址时才允许展开
                    if !apiService.server.alternateURLs.isEmpty {
                        withAnimation { showAddressList.toggle() }
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: apiService.activeBaseURL.absoluteString.hasPrefix("https") ? "cloud.fill" : "server.rack")
                            .font(.system(size: 18))
                            .foregroundStyle(.gray)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(apiService.server.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            MarqueeText(text: displayURLForActiveAddress, font: .caption, style: .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // 健康状态指示
                        HStack(spacing: 6) {
                            Circle()
                                .fill(healthStatusColor)
                                .frame(width: 8, height: 8)

                            Text(healthStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // 有备用地址时显示展开箭头
                        if !apiService.server.alternateURLs.isEmpty {
                            Image(systemName: showAddressList ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 展开的地址列表
                if showAddressList {
                    Divider()
                        .padding(.vertical, AppTheme.Spacing.sm)

                    addressListContent
                }
            }
        }
    }

    /// 当前活动地址的简短显示
    private var displayURLForActiveAddress: String {
        apiService.activeBaseURL.absoluteString
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
    }

    /// 地址列表内容
    private var addressListContent: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(apiService.server.allURLs, id: \.self) { urlString in
                let isActive = urlString == apiService.activeBaseURL.absoluteString

                Button {
                    if !isActive {
                        switchAddress(to: urlString)
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(isActive ? .green : Color.gray)
                            .frame(width: 24)

                        // http 用服务器图标，https 用云图标
                        Image(systemName: urlString.hasPrefix("https") ? "cloud.fill" : "server.rack")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        MarqueeText(
                            text: urlString
                                .replacingOccurrences(of: "http://", with: "")
                                .replacingOccurrences(of: "https://", with: ""),
                            font: .subheadline,
                            style: .primary
                        )

                        if isSwitchingURL && !isActive {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, AppTheme.Spacing.xxs)
                }
                .buttonStyle(.plain)
                .disabled(isActive || isSwitchingURL)
            }
        }
    }

    /// 切换到指定地址
    private func switchAddress(to urlString: String) {
        guard let newURL = URL(string: urlString) else {
            GlassAlertManager.shared.showError("无效地址")
            return
        }

        let previousURL = apiService.activeBaseURL
        isSwitchingURL = true

        Task {
            // 先切换地址
            await apiService.switchToURL(newURL)

            // 验证连接
            let status = await apiService.checkConnection()

            if status == .online {
                healthStatus = .online
                isSwitchingURL = false
                GlassAlertManager.shared.showSuccess("已切换到新地址")
            } else {
                // 连接失败，回退到原来的地址
                await apiService.switchToURL(previousURL)
                healthStatus = await apiService.checkConnection()
                isSwitchingURL = false
                GlassAlertManager.shared.showError("切换失败", message: "无法连接到该地址，已恢复原地址")
            }
        }
    }

    private var healthStatusColor: Color {
        switch healthStatus {
        case .online: return .green
        case .authError: return .red
        case .offline: return .red
        case .checking: return .orange
        }
    }

    private var healthStatusText: String {
        switch healthStatus {
        case .online: return "在线"
        case .authError: return "认证错误"
        case .offline: return "离线"
        case .checking: return "检查中"
        }
    }

    // MARK: - 2. 源文件夹

    private var sourceFolderSection: some View {
        SettingsSection(title: "源文件夹") {
            VStack(spacing: 0) {
                // 当前源文件夹
                Button {
                    withAnimation { showSourceFolderList.toggle() }
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.yellow)
                            .frame(width: 28)

                        Text(currentSourceFolderName)
                            .font(.body)
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: showSourceFolderList ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 展开的源文件夹列表
                if showSourceFolderList {
                    Divider()
                        .padding(.vertical, AppTheme.Spacing.sm)

                    sourceFolderListContent
                }
            }
        }
    }

    private var currentSourceFolderName: String {
        if let folders = sourceFolders {
            return URL(fileURLWithPath: folders.current).lastPathComponent
        }
        return "加载中..."
    }

    /// 源文件夹列表内容
    private var sourceFolderListContent: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if let folders = sourceFolders {
                // 当前源文件夹
                sourceFolderRow(path: folders.current, isCurrent: true)

                // 备用源文件夹
                ForEach(folders.backups, id: \.self) { backup in
                    sourceFolderRow(path: backup, isCurrent: false)
                }
            }
        }
    }

    @ViewBuilder
    private func sourceFolderRow(path: String, isCurrent: Bool) -> some View {
        let name = URL(fileURLWithPath: path).lastPathComponent

        HStack(spacing: AppTheme.Spacing.sm) {
            Button {
                if !isCurrent {
                    switchSourceFolder(to: path)
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isCurrent ? .green : Color.gray)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.vertical, AppTheme.Spacing.xxs)
            }
            .buttonStyle(.plain)
            .disabled(isCurrent)

            // 当前源文件夹显示重新索引按钮
            if isCurrent {
                Button {
                    reindexCurrentSourceFolder()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 3. 语言切换

    private var languageSection: some View {
        SettingsSection(title: "语言") {
            Picker("语言", selection: $language) {
                Text("中文").tag(LocalStorageService.AppSettings.Language.zh)
                Text("English").tag(LocalStorageService.AppSettings.Language.en)
            }
            .pickerStyle(.segmented)
            .onChange(of: language) { _, newValue in
                var settings = LocalStorageService.shared.getAppSettings()
                settings.language = newValue
                LocalStorageService.shared.saveAppSettings(settings)
            }
        }
    }

    // MARK: - 4. 主题切换

    private var themeSection: some View {
        SettingsSection(title: "主题") {
            Picker("主题", selection: $themePreference) {
                Image(systemName: "sun.max.fill").tag(LocalStorageService.AppSettings.DarkModePreference.light)
                Image(systemName: "moon.fill").tag(LocalStorageService.AppSettings.DarkModePreference.dark)
                Image(systemName: "circle.lefthalf.filled").tag(LocalStorageService.AppSettings.DarkModePreference.system)
            }
            .pickerStyle(.segmented)
            .onChange(of: themePreference) { _, newValue in
                var settings = LocalStorageService.shared.getAppSettings()
                settings.darkModePreference = newValue
                LocalStorageService.shared.saveAppSettings(settings)
                NotificationCenter.default.post(name: .themeDidChange, object: nil)
            }
        }
    }

    // MARK: - 5. 偏好设置

    private var preferencesSection: some View {
        SettingsSection(title: "偏好") {
            NavigationLink {
                PreferencesView(apiService: apiService)
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)
                        .frame(width: 28)
                    Text("偏好设置")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 6. 认证

    private var authSection: some View {
        SettingsSection(title: "认证") {
            NavigationLink {
                AuthSettingsView(apiService: apiService)
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)
                        .frame(width: 28)

                    Text("平台认证")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 7. 下载器

    private var downloaderSection: some View {
        SettingsSection(title: "下载器") {
            NavigationLink {
                DownloaderSettingsView(apiService: apiService)
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                        .frame(width: 28)

                    Text("下载器管理")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 8. 缓存管理

    private var cacheSection: some View {
        SettingsSection(title: "缓存") {
            NavigationLink {
                CacheSettingsView()
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                        .frame(width: 28)

                    Text("缓存管理")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer()

                    if !totalCacheSize.isEmpty {
                        Text(totalCacheSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 7. 关于

    private var aboutSection: some View {
        SettingsSection(title: "关于") {
            VStack(spacing: AppTheme.Spacing.md) {
                // iOS App 版本
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                HStack {
                    Text("iOS 版本")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Text(appVersion)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        if let latest = latestIOSVersion, latest != appVersion {
                            Text(latest)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.blue))
                        }
                    }
                }

                Divider()

                // 服务器版本 + 检查更新
                HStack {
                    Text("服务器版本")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Text(appConfig?.version ?? "...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        if let latest = latestServerVersion, latest != appConfig?.version {
                            Text(latest)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.blue))
                            Button {
                                Task { await triggerServerUpdate() }
                            } label: {
                                Image(systemName: isUpdatingServer ? "arrow.trianglehead.2.clockwise" : "arrow.down.circle")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            .disabled(isUpdatingServer)
                        }
                    }
                }

                Divider()

                // 链接按钮
                HStack(spacing: AppTheme.Spacing.md) {
                    if let iosUrl = appConfig?.iosUrl, let url = URL(string: iosUrl) {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            HStack(spacing: AppTheme.Spacing.xs) {
                                Image(systemName: "iphone")
                                    .font(.caption)
                                Text("iOS 下载")
                                    .font(.caption)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .clearGlassBackground(in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        openGitHub()
                    } label: {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Image("GithubIcon")
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                            Text("GitHub")
                                .font(.caption)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .clearGlassBackground(in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // 检查更新按钮
                    Button {
                        Task { await checkAllUpdates() }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            if isCheckingUpdate {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                            }
                            Text("检查更新")
                                .font(.caption)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .clearGlassBackground(in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isCheckingUpdate)
                }
            }
        }
    }

    // MARK: - 8. 断开连接

    private var disconnectSection: some View {
        SettingsSection(title: "") {
            Button {
                showDisconnectConfirm = true
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .frame(width: 28)

                    Text("断开连接")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 版本信息

    private var versionFooter: some View {
        VStack(spacing: 4) {
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            let serverVersion = appConfig?.version ?? "..."

            Text("App \(appVersion) · Server \(serverVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.xxl)
    }

    // MARK: - Methods

    private func loadSettings() async {
        // 加载本地设置
        let settings = LocalStorageService.shared.getAppSettings()
        themePreference = settings.darkModePreference
        language = settings.language

        // 并发加载远程数据
        async let healthTask: () = loadHealth()
        async let configTask: () = loadAppConfig()
        async let sourcesTask: () = loadSourceFolders()
        async let cacheTask: () = loadCacheSize()

        _ = await (healthTask, configTask, sourcesTask, cacheTask)
    }

    private func loadHealth() async {
        do {
            let health = try await apiService.auth.checkHealth()
            healthStatus = health.status == "ok" ? .online : .offline
        } catch {
            healthStatus = .offline
        }
    }

    private func loadAppConfig() async {
        do {
            appConfig = try await apiService.auth.getAppConfig()
        } catch {
            // 静默失败
        }
    }

    private func loadSourceFolders() async {
        do {
            sourceFolders = try await apiService.config.getSourceFolders()
        } catch {
            // 静默失败
        }
    }

    private func loadCacheSize() async {
        let size = await Task.detached(priority: .utility) {
            let thumb = ThumbnailCacheService.shared.diskCacheSize()
            let video = ThumbnailCacheService.videoCacheSize()
            let network = ThumbnailCacheService.networkCacheSize()
            let temp = ThumbnailCacheService.appTempSize()
            return thumb + video + network + temp
        }.value
        totalCacheSize = ThumbnailCacheService.formatSize(size)
    }

    private func reindexCurrentSourceFolder() {
        guard let current = sourceFolders?.current else { return }
        Task {
            do {
                let response = try await apiService.preview.scanIndexer(sourceFolder: current, force: true)
                if response.status == "already_scanning" {
                    GlassAlertManager.shared.showWarning("正在扫描中")
                    return
                }
                // 显示进度弹窗，开始轮询
                isReindexing = true
                await pollReindexStatus()
                isReindexing = false
                GlassAlertManager.shared.showSuccess("重新索引完成")
            } catch {
                isReindexing = false
                GlassAlertManager.shared.showError("索引失败", message: error.localizedDescription)
            }
        }
    }

    private func pollReindexStatus() async {
        // 等待服务端启动扫描（避免竞态：scan 触发后 isScanning 可能还未置 true）
        try? await Task.sleep(for: .milliseconds(800))

        var consecutiveNotScanning = 0
        while true {
            do {
                let status = try await apiService.preview.getIndexerStatus()
                if !status.isScanning {
                    // 连续两次拿到 false 才认为真正结束，防止单次误报
                    consecutiveNotScanning += 1
                    if consecutiveNotScanning >= 2 { break }
                } else {
                    consecutiveNotScanning = 0
                }
            } catch {
                break
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func switchSourceFolder(to path: String) {
        Task {
            do {
                GlassAlertManager.shared.showQuickLoading()
                try await apiService.config.switchSourceFolder(to: path)
                sourceFolders = try await apiService.config.getSourceFolders()
                GlassAlertManager.shared.hideQuickLoading()
                showSourceFolderList = false
                GlassAlertManager.shared.showSuccess("已切换源文件夹")
                NotificationCenter.default.post(name: .sourceFolderDidChange, object: nil)
            } catch {
                GlassAlertManager.shared.hideQuickLoading()
                GlassAlertManager.shared.showError("切换失败", message: error.localizedDescription)
            }
        }
    }

    private func checkAllUpdates() async {
        isCheckingUpdate = true

        // 并行检查服务器和 iOS 版本
        async let serverCheck: Void = {
            do {
                let result = try await apiService.config.checkUpdate()
                await MainActor.run { latestServerVersion = result.latestVersion }
            } catch {}
        }()

        async let iosCheck: Void = {
            if let version = await Self.fetchPgyerVersion() {
                await MainActor.run { latestIOSVersion = version }
            }
        }()

        _ = await (serverCheck, iosCheck)

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let hasServerUpdate = latestServerVersion != nil && latestServerVersion != appConfig?.version
        let hasIOSUpdate = latestIOSVersion != nil && latestIOSVersion != appVersion

        if hasServerUpdate || hasIOSUpdate {
            var parts: [String] = []
            if hasIOSUpdate, let v = latestIOSVersion { parts.append("iOS \(v)") }
            if hasServerUpdate, let v = latestServerVersion { parts.append("Server \(v)") }
            GlassAlertManager.shared.showSuccess("发现新版本: \(parts.joined(separator: ", "))")
        } else {
            GlassAlertManager.shared.showSuccess("已是最新版本")
        }

        isCheckingUpdate = false
    }

    private func triggerServerUpdate() async {
        isUpdatingServer = true
        do {
            let result = try await apiService.config.updateServer()
            GlassAlertManager.shared.showSuccess(result.message)
        } catch {
            GlassAlertManager.shared.showError("更新失败: \(error.localizedDescription)")
        }
        isUpdatingServer = false
    }

    /// 从蒲公英公开页面抓取最新 iOS 版本号
    private static func fetchPgyerVersion() async -> String? {
        guard let url = URL(string: "https://www.pgyer.com/resourcer-ios") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            // 匹配页面中的 aVersion = '0.0.16' 变量
            let pattern = #"aVersion\s*=\s*'([^']+)'"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        } catch {
            return nil
        }
    }

    private func openGitHub() {
        let urlString = appConfig?.githubUrl ?? "https://github.com"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    private func disconnect() {
        LocalStorageService.shared.logout()
        NotificationCenter.default.post(name: .userDidLogout, object: nil)
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.leading, AppTheme.Spacing.sm)
            }

            content()
                .padding(AppTheme.Spacing.md)
                .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
        }
    }
}

// MARK: - Settings Row

struct SettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let trailing: () -> Trailing
    let action: (() -> Void)?

    init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String?,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.action = action
    }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                trailing()

                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// MARK: - Settings Toggle Row

struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.gray)
        }
    }
}

// MARK: - Marquee Text

/// 跑马灯文本：文本溢出容器宽度时自动来回滚动
private struct MarqueeText<S: ShapeStyle>: View {
    let text: String
    let font: Font
    let style: S

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(style)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: -offset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            // 测量容器宽度
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in containerWidth = w }
                }
            )
            // 测量文本实际宽度
            .overlay(
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear { textWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in textWidth = w }
                    })
                    .hidden()
            )
            .task(id: overflow) {
                guard overflow > 0 else {
                    offset = 0
                    return
                }
                let duration = max(1.5, Double(overflow) / 40)
                // 初始停顿
                try? await Task.sleep(for: .seconds(1.5))
                while !Task.isCancelled {
                    // 向左滚动
                    withAnimation(.easeInOut(duration: duration)) {
                        offset = overflow
                    }
                    try? await Task.sleep(for: .seconds(duration + 1.5))
                    guard !Task.isCancelled else { break }
                    // 滚回原位
                    withAnimation(.easeInOut(duration: duration)) {
                        offset = 0
                    }
                    try? await Task.sleep(for: .seconds(duration + 1.5))
                }
            }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let userDidLogout = Notification.Name("userDidLogout")
    static let themeDidChange = Notification.Name("themeDidChange")
    static let serverDidSwitch = Notification.Name("serverDidSwitch")
    static let sourceFolderDidChange = Notification.Name("sourceFolderDidChange")
    /// 当 NetworkManager 检测到连接错误时发送（用于触发全局切换地址对话框）
    static let networkConnectivityError = Notification.Name("networkConnectivityError")
}

// MARK: - Preview

#Preview {
    let server = Server(name: "Test Server", baseURL: "http://localhost:1234", apiKey: "test")
    if let api = APIService.create(for: server) {
        SettingsView(apiService: api)
            .previewWithGlassBackground()
    }
}
