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

    @State private var configState: ConfigStateResponse?
    @State private var downloadConfig: DownloadConfigResponse?
    @State private var isLoading = false

    // 源文件夹管理
    @State private var showSourceFolderPicker = false
    @State private var sourceFolders: SourceFoldersResponse?

    // 认证管理
    @State private var showCredentialEditor = false
    @State private var selectedPlatform: AuthPlatform?

    // 断开连接
    @State private var showDisconnectConfirm = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            navigationBar

            // 设置列表
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    // 服务器信息
                    serverInfoSection

                    // 源文件夹管理
                    sourceFolderSection

                    // 下载器设置
                    downloaderSection

                    // 认证管理
                    authSection

                    // 关于
                    aboutSection

                    // 断开连接
                    disconnectSection
                }
                .padding(AppTheme.Spacing.lg)
            }
        }
        .task {
            await loadSettings()
        }
        .glassDeleteConfirm(
            isPresented: $showDisconnectConfirm,
            title: "断开连接？",
            message: "将退出当前服务器"
        ) {
            disconnect()
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        GlassNavigationBar(
            title: "设置",
            trailing: {
                GlassNavBarButton("arrow.clockwise") {
                    Task { await loadSettings() }
                }
            }
        )
    }

    // MARK: - Server Info Section

    private var serverInfoSection: some View {
        SettingsSection(title: "服务器") {
            VStack(spacing: AppTheme.Spacing.sm) {
                SettingsRow(
                    icon: "server.rack",
                    iconColor: .blue,
                    title: apiService.server.name,
                    subtitle: apiService.server.displayURL
                )

                if let config = downloadConfig {
                    SettingsRow(
                        icon: "arrow.down.app",
                        iconColor: .green,
                        title: "yt-dlp",
                        subtitle: config.ytdlpVersion
                    )
                }
            }
        }
    }

    // MARK: - Source Folder Section

    private var sourceFolderSection: some View {
        SettingsSection(title: "源文件夹") {
            VStack(spacing: AppTheme.Spacing.sm) {
                if let config = configState {
                    SettingsRow(
                        icon: "folder.fill",
                        iconColor: .yellow,
                        title: "当前文件夹",
                        subtitle: config.sourceFolder.components(separatedBy: "/").last ?? config.sourceFolder,
                        action: {
                            showSourceFolderPicker = true
                        }
                    )

                    if !config.backupSourceFolders.isEmpty {
                        SettingsRow(
                            icon: "folder.badge.plus",
                            iconColor: .orange,
                            title: "备用文件夹",
                            subtitle: "\(config.backupSourceFolders.count) 个",
                            action: {
                                showSourceFolderPicker = true
                            }
                        )
                    }
                } else {
                    SettingsRow(
                        icon: "folder",
                        iconColor: .gray,
                        title: "加载中...",
                        subtitle: nil
                    )
                }
            }
        }
    }

    // MARK: - Downloader Section

    private var downloaderSection: some View {
        SettingsSection(title: "下载器") {
            VStack(spacing: AppTheme.Spacing.sm) {
                if let config = downloadConfig {
                    SettingsToggleRow(
                        icon: "globe",
                        iconColor: .purple,
                        title: "使用 Cookies",
                        subtitle: "某些网站需要登录才能下载",
                        isOn: .constant(config.useCookies)
                    )
                }

                if let hiddenCount = configState?.hiddenFolders.count, hiddenCount > 0 {
                    SettingsRow(
                        icon: "eye.slash",
                        iconColor: .gray,
                        title: "隐藏文件夹",
                        subtitle: "\(hiddenCount) 个"
                    )
                }
            }
        }
    }

    // MARK: - Auth Section

    private var authSection: some View {
        SettingsSection(title: "平台认证") {
            VStack(spacing: AppTheme.Spacing.sm) {
                if let config = downloadConfig {
                    // X (Twitter)
                    SettingsRow(
                        icon: "xmark.circle.fill",
                        iconColor: .blue,
                        title: "X (Twitter)",
                        subtitle: config.authStatus.x ? "已配置" : "未配置",
                        trailing: {
                            statusBadge(isConfigured: config.authStatus.x)
                        }
                    ) {
                        selectedPlatform = .x
                        showCredentialEditor = true
                    }

                    // Pixiv
                    SettingsRow(
                        icon: "paintbrush.fill",
                        iconColor: .blue,
                        title: "Pixiv",
                        subtitle: config.authStatus.pixiv ? "已配置" : "未配置",
                        trailing: {
                            statusBadge(isConfigured: config.authStatus.pixiv)
                        }
                    ) {
                        selectedPlatform = .pixiv
                        showCredentialEditor = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(isConfigured: Bool) -> some View {
        Image(systemName: isConfigured ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(isConfigured ? .green : .gray)
    }

    // MARK: - About Section

    private var aboutSection: some View {
        SettingsSection(title: "关于") {
            VStack(spacing: AppTheme.Spacing.sm) {
                SettingsRow(
                    icon: "info.circle",
                    iconColor: .blue,
                    title: "版本",
                    subtitle: "1.0.0"
                )

                SettingsRow(
                    icon: "link",
                    iconColor: .blue,
                    title: "GitHub",
                    subtitle: "查看源代码"
                ) {
                    // TODO: 打开 GitHub 链接
                }

                if let presets = configState?.presets, !presets.isEmpty {
                    SettingsRow(
                        icon: "square.stack.3d.up",
                        iconColor: .purple,
                        title: "预设",
                        subtitle: "\(presets.count) 个可用"
                    )
                }
            }
        }
    }

    // MARK: - Disconnect Section

    private var disconnectSection: some View {
        VStack {
            GlassButton.destructive("断开连接", icon: "rectangle.portrait.and.arrow.right") {
                showDisconnectConfirm = true
            }
        }
        .padding(.top, AppTheme.Spacing.lg)
    }

    // MARK: - Methods

    private func loadSettings() async {
        isLoading = true

        do {
            async let configTask = apiService.config.getConfigState()
            async let downloadTask = apiService.config.getDownloadConfig()
            async let sourcesTask = apiService.config.getSourceFolders()

            configState = try await configTask
            downloadConfig = try await downloadTask
            sourceFolders = try await sourcesTask

        } catch {
            GlassAlertManager.shared.showError("加载失败", message: error.localizedDescription)
        }

        isLoading = false
    }

    private func disconnect() {
        LocalStorageService.shared.logout()
        // App 会自动检测登录状态变化并切换到登录页面
        // 这里需要通知 App 层刷新状态
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
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.leading, AppTheme.Spacing.sm)

            content()
                .padding(AppTheme.Spacing.md)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
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
                        .foregroundStyle(.white)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                trailing()

                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
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
                    .foregroundStyle(.white)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.green)
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let userDidLogout = Notification.Name("userDidLogout")
}

// MARK: - Preview

#Preview {
    let server = Server(name: "Test Server", baseURL: "http://localhost:1234", apiKey: "test")
    if let api = APIService.create(for: server) {
        SettingsView(apiService: api)
            .previewWithGlassBackground()
    }
}
