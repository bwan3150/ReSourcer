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
    @State private var serverName = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    /// 已保存的服务器列表
    @State private var savedServers: [Server] = []

    /// 是否显示添加/编辑服务器表单
    @State private var showForm = false

    /// 正在编辑的服务器（nil 表示添加新服务器）
    @State private var editingServer: Server?

    // MARK: - Body

    var body: some View {
        ZStack {
            // 背景
            LinearGradient(
                colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.1)],
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
                    if !savedServers.isEmpty && !showForm {
                        savedServersSection
                    }

                    // 添加/编辑服务器表单
                    if showForm || savedServers.isEmpty {
                        serverFormSection
                    } else {
                        // 添加新服务器按钮
                        Button {
                            withAnimation {
                                editingServer = nil
                                serverURL = ""
                                apiKey = ""
                                serverName = ""
                                showForm = true
                            }
                        } label: {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                Text("添加新服务器")
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, AppTheme.Spacing.lg)
                            .padding(.vertical, AppTheme.Spacing.md)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
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
                .foregroundStyle(.primary)
                .padding(AppTheme.Spacing.lg)
                .glassEffect(.regular, in: .circle)

            Text("ReSourcer")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text("连接到您的服务器开始使用")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, AppTheme.Spacing.xxxl)
    }

    // MARK: - Saved Servers Section

    private var savedServersSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("已保存的服务器")
                .font(.headline)
                .foregroundStyle(.primary)

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
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)

            // 服务器信息
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(server.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(server.displayURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 编辑按钮
            Button {
                editServer(server)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .glassEffect(.clear.interactive(), in: .circle)

            // 连接按钮
            Button {
                connect(to: server)
            } label: {
                Text("连接")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .glassEffect(.regular.interactive(), in: .capsule)

            // 删除按钮
            Button {
                deleteServer(server)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(AppTheme.Spacing.md)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }

    // MARK: - Server Form Section

    private var serverFormSection: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // 标题栏
            HStack {
                Text(editingServer != nil ? "编辑服务器" : "添加新服务器")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if !savedServers.isEmpty {
                    Button("取消") {
                        withAnimation {
                            showForm = false
                            editingServer = nil
                            errorMessage = nil
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            // 服务器名称
            GlassTextField(
                "服务器名称（可选）",
                text: $serverName,
                placeholder: "我的服务器",
                icon: "tag"
            )
            .textInputAutocapitalization(.never)

            // 服务器地址
            GlassTextField(
                "服务器地址",
                text: $serverURL,
                placeholder: "http://192.168.1.100:1234",
                icon: "link"
            )
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)

            // API Key
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

            // 按钮
            HStack(spacing: AppTheme.Spacing.md) {
                if editingServer != nil {
                    // 保存按钮（编辑模式）
                    Button {
                        saveEditedServer()
                    } label: {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "checkmark")
                            Text("保存")
                        }
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .disabled(serverURL.isEmpty || apiKey.isEmpty)
                }

                // 连接按钮
                Button {
                    if editingServer != nil {
                        saveAndConnect()
                    } else {
                        connectWithInput()
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "arrow.right.circle.fill")
                        Text(editingServer != nil ? "保存并连接" : "连接服务器")
                    }
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.md)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .disabled(serverURL.isEmpty || apiKey.isEmpty)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
    }

    // MARK: - Methods

    private func loadSavedServers() {
        savedServers = LocalStorageService.shared.getServers()
    }

    private func editServer(_ server: Server) {
        editingServer = server
        serverName = server.name
        serverURL = server.baseURL
        apiKey = server.apiKey
        errorMessage = nil
        withAnimation {
            showForm = true
        }
    }

    private func saveEditedServer() {
        guard let oldServer = editingServer else { return }

        let updatedServer = Server(
            id: oldServer.id,
            name: serverName.isEmpty ? extractServerName(from: serverURL) : serverName,
            baseURL: normalizeURL(serverURL),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        LocalStorageService.shared.updateServer(updatedServer)
        loadSavedServers()

        withAnimation {
            showForm = false
            editingServer = nil
        }

        GlassAlertManager.shared.showSuccess("服务器已更新")
    }

    private func saveAndConnect() {
        guard let oldServer = editingServer else { return }

        let updatedServer = Server(
            id: oldServer.id,
            name: serverName.isEmpty ? extractServerName(from: serverURL) : serverName,
            baseURL: normalizeURL(serverURL),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        LocalStorageService.shared.updateServer(updatedServer)
        loadSavedServers()
        connect(to: updatedServer)
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
                    showForm = false
                    editingServer = nil
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
        let url = normalizeURL(serverURL)

        let server = Server(
            name: serverName.isEmpty ? extractServerName(from: url) : serverName,
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
                    serverName = ""
                    showForm = false

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

    private func normalizeURL(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "http://" + normalized
        }
        return normalized
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
