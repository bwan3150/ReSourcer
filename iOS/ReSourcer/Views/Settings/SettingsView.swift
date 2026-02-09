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

                    // 5. 认证
                    authSection

                    // 6. 缓存管理
                    cacheSection

                    // 7. GitHub
                    githubSection

                    // 7. 断开连接
                    disconnectSection

                    // 8. 版本信息
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
    }

    // MARK: - 1. 服务器状态

    private var serverSection: some View {
        SettingsSection(title: "服务器") {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "server.rack")
                    .font(.system(size: 18))
                    .foregroundStyle(.gray)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(apiService.server.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(apiService.server.displayURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 健康状态指示
                HStack(spacing: 6) {
                    Circle()
                        .fill(healthStatusColor)
                        .frame(width: 8, height: 8)

                    Text(healthStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    // MARK: - 5. 认证

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

    // MARK: - 6. 缓存管理

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

    // MARK: - 7. GitHub

    private var githubSection: some View {
        SettingsSection(title: "") {
            Button {
                openGitHub()
            } label: {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image("GithubIcon")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.primary)
                        .frame(width: 28)

                    Text("在 GitHub 上查看")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

    // MARK: - 8. 版本信息

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

    private func switchSourceFolder(to path: String) {
        Task {
            do {
                try await apiService.config.switchSourceFolder(to: path)
                sourceFolders = try await apiService.config.getSourceFolders()
                showSourceFolderList = false
                GlassAlertManager.shared.showSuccess("已切换源文件夹")
            } catch {
                GlassAlertManager.shared.showError("切换失败", message: error.localizedDescription)
            }
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

// MARK: - Notification Name

extension Notification.Name {
    static let userDidLogout = Notification.Name("userDidLogout")
    static let themeDidChange = Notification.Name("themeDidChange")
    static let serverDidSwitch = Notification.Name("serverDidSwitch")
}

// MARK: - Preview

#Preview {
    let server = Server(name: "Test Server", baseURL: "http://localhost:1234", apiKey: "test")
    if let api = APIService.create(for: server) {
        SettingsView(apiService: api)
            .previewWithGlassBackground()
    }
}
