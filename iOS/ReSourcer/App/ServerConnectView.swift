//
//  ServerConnectView.swift
//  ReSourcer
//
//  服务器连接/登录界面
//

import SwiftUI

struct ServerConnectView: View {

    // MARK: - Properties

    let onConnected: (APIService) -> Void

    @State private var serverURL = ""
    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    /// 已保存的服务器列表
    @State private var savedServers: [Server] = []

    /// 是否显示添加服务器表单
    @State private var showAddForm = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // 背景
            LinearGradient(
                colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 内容
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xxl) {
                    // Logo 和标题
                    headerSection

                    // 已保存的服务器列表
                    if !savedServers.isEmpty && !showAddForm {
                        savedServersSection
                    }

                    // 添加新服务器
                    if showAddForm || savedServers.isEmpty {
                        addServerSection
                    } else {
                        // 添加新服务器按钮
                        GlassButton.secondary("添加新服务器", icon: "plus") {
                            withAnimation {
                                showAddForm = true
                            }
                        }
                    }

                    Spacer(minLength: 50)
                }
                .padding(AppTheme.Spacing.lg)
            }
        }
        .onAppear {
            loadSavedServers()
        }
        .glassLoading(isLoading: isConnecting, message: "正在连接...")
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // App 图标
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.white)
                .padding(AppTheme.Spacing.lg)
                .glassEffect(.regular, in: .circle)

            Text("ReSourcer")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("连接到您的服务器开始使用")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, AppTheme.Spacing.xxxl)
    }

    // MARK: - Saved Servers Section

    private var savedServersSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("已保存的服务器")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(savedServers) { server in
                serverRow(server)
            }
        }
    }

    @ViewBuilder
    private func serverRow(_ server: Server) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // 服务器图标
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)

            // 服务器信息
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(server.name)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(server.displayURL)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            // 连接按钮
            GlassButton("连接", style: .primary, size: .small) {
                connect(to: server)
            }

            // 删除按钮
            Button {
                deleteServer(server)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(AppTheme.Spacing.md)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }

    // MARK: - Add Server Section

    private var addServerSection: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            if showAddForm && !savedServers.isEmpty {
                HStack {
                    Text("添加新服务器")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Spacer()

                    Button("取消") {
                        withAnimation {
                            showAddForm = false
                            errorMessage = nil
                        }
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
            }

            GlassTextField(
                "服务器地址",
                text: $serverURL,
                placeholder: "http://192.168.1.100:1234",
                icon: "link"
            )
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)

            GlassTextField(
                "API Key",
                text: $apiKey,
                placeholder: "输入 API Key",
                icon: "key",
                isSecure: true
            )
            .textInputAutocapitalization(.never)

            // 错误提示
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error)
                }
                .font(.caption)
                .foregroundStyle(.red)
            }

            // 连接按钮
            GlassButton.primary("连接服务器", icon: "arrow.right", size: .large) {
                connectWithInput()
            }
            .disabled(serverURL.isEmpty || apiKey.isEmpty)
        }
        .padding(AppTheme.Spacing.lg)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
    }

    // MARK: - Methods

    private func loadSavedServers() {
        savedServers = LocalStorageService.shared.getServers()
    }

    private func connect(to server: Server) {
        guard let apiService = APIService.create(for: server) else {
            errorMessage = "无效的服务器地址"
            return
        }

        isConnecting = true
        errorMessage = nil

        Task {
            let status = await apiService.checkConnection()

            await MainActor.run {
                isConnecting = false

                switch status {
                case .online:
                    LocalStorageService.shared.setCurrentServer(server.id)
                    LocalStorageService.shared.setLoggedIn(true)
                    onConnected(apiService)

                case .authError:
                    errorMessage = "API Key 无效"

                case .offline:
                    errorMessage = "无法连接到服务器"

                case .checking:
                    errorMessage = "连接超时"
                }
            }
        }
    }

    private func connectWithInput() {
        // 标准化 URL
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "http://" + url
        }

        let server = Server(
            name: extractServerName(from: url),
            baseURL: url,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard let apiService = APIService.create(for: server) else {
            errorMessage = "无效的服务器地址"
            return
        }

        isConnecting = true
        errorMessage = nil

        Task {
            let status = await apiService.checkConnection()

            await MainActor.run {
                isConnecting = false

                switch status {
                case .online:
                    // 保存服务器
                    LocalStorageService.shared.addServer(server)
                    LocalStorageService.shared.setCurrentServer(server.id)
                    LocalStorageService.shared.setLoggedIn(true)

                    // 清空输入
                    serverURL = ""
                    apiKey = ""
                    showAddForm = false

                    onConnected(apiService)

                case .authError:
                    errorMessage = "API Key 无效"

                case .offline:
                    errorMessage = "无法连接到服务器"

                case .checking:
                    errorMessage = "连接超时"
                }
            }
        }
    }

    private func deleteServer(_ server: Server) {
        LocalStorageService.shared.deleteServer(server.id)
        loadSavedServers()
    }

    private func extractServerName(from url: String) -> String {
        if let host = URL(string: url)?.host {
            return host
        }
        return "服务器"
    }
}

// MARK: - Preview

#Preview {
    ServerConnectView { _ in
        print("Connected!")
    }
}
