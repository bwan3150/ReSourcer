//
//  ServerConnectView.swift
//  ReSourcer
//
//  服务器连接/登录界面
//

import SwiftUI
import CoreMotion

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

    /// 是否显示扫码器
    @State private var showScanner = false

    /// 陀螺仪 / 拖拽姿态
    @State private var pitch: Double = 0
    @State private var roll: Double = 0
    @State private var isDragging = false
    @State private var motionManager: CMMotionManager?

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

            // 内容 — 使用 List 以支持 swipeActions
            List {
                // Logo
                headerSection
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: AppTheme.Spacing.lg, bottom: 0, trailing: AppTheme.Spacing.lg))

                // 已保存的服务器列表
                if !savedServers.isEmpty {
                    ForEach(savedServers) { server in
                        serverRow(server)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteServer(server)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }

                                Button {
                                    editServer(server)
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: AppTheme.Spacing.xs, leading: AppTheme.Spacing.lg, bottom: AppTheme.Spacing.xs, trailing: AppTheme.Spacing.lg))
                }

                // 没有服务器时显示内联表单
                if savedServers.isEmpty {
                    serverFormSection
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: AppTheme.Spacing.md, leading: AppTheme.Spacing.lg, bottom: 0, trailing: AppTheme.Spacing.lg))
                } else {
                    // 添加按钮（仅图标）
                    HStack {
                        Spacer()
                        Button {
                            editingServer = nil
                            serverURL = ""
                            apiKey = ""
                            serverName = ""
                            errorMessage = nil
                            showForm = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: AppTheme.Spacing.md, leading: AppTheme.Spacing.lg, bottom: 0, trailing: AppTheme.Spacing.lg))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .onAppear {
            loadSavedServers()
        }
        .glassLoading(isLoading: isConnecting, message: "正在连接...")
        // 添加/编辑服务器弹窗（有已保存服务器时使用）
        .glassBottomSheet(
            isPresented: $showForm,
            showHandle: true,
            showCloseButton: false,
            onDismiss: {
                editingServer = nil
                errorMessage = nil
            }
        ) {
            serverFormSection
        }
        // 扫码全屏页
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView { info in
                serverURL = info.serverURL
                apiKey = info.apiKey
                showScanner = false
            } onDismiss: {
                showScanner = false
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            Spacer()
            ZStack {
                // 底层光晕 — 跟随陀螺仪偏移
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.25), .cyan.opacity(0.08), .clear],
                            center: UnitPoint(
                                x: 0.5 + roll * 0.3,
                                y: 0.5 - pitch * 0.3
                            ),
                            startRadius: 10,
                            endRadius: 90
                        )
                    )
                    .frame(width: 150, height: 150)
                    .blur(radius: 20)

                // Icon 主体
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 110, height: 110)
                    .clipShape(Circle())
                    // 高光反射 — 模拟玻璃折射
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.5),
                                        .white.opacity(0.1),
                                        .clear,
                                        .clear,
                                    ],
                                    startPoint: UnitPoint(
                                        x: 0.2 + roll * 0.3,
                                        y: 0.0 - pitch * 0.2
                                    ),
                                    endPoint: UnitPoint(
                                        x: 0.8 + roll * 0.3,
                                        y: 1.0 - pitch * 0.2
                                    )
                                )
                            )
                            .blendMode(.overlay)
                    )
                    // 玻璃边框
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.6),
                                        .white.opacity(0.1),
                                        .white.opacity(0.3),
                                    ],
                                    startPoint: UnitPoint(
                                        x: 0.3 + roll * 0.2,
                                        y: 0.0 - pitch * 0.2
                                    ),
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.5
                            )
                    )
                    // 3D 旋转 — 跟随设备姿态
                    .rotation3DEffect(
                        .degrees(roll * 12),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.4
                    )
                    .rotation3DEffect(
                        .degrees(pitch * 10),
                        axis: (x: -1, y: 0, z: 0),
                        perspective: 0.4
                    )
                    // 动态阴影 — 随倾斜偏移
                    .shadow(
                        color: .black.opacity(0.25),
                        radius: 16,
                        x: CGFloat(roll * 10),
                        y: CGFloat(pitch * 10) + 6
                    )
                    // 手指拖拽手势
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    motionManager?.stopDeviceMotionUpdates()
                                }
                                // 拖拽距离 → 姿态值（±0.6 弧度范围）
                                withAnimation(.interactiveSpring(duration: 0.08)) {
                                    roll = min(max(Double(value.translation.width / 150), -0.6), 0.6)
                                    pitch = min(max(Double(-value.translation.height / 150), -0.6), 0.6)
                                }
                            }
                            .onEnded { _ in
                                isDragging = false
                                // 弹回原位
                                withAnimation(.spring(duration: 0.6, bounce: 0.4)) {
                                    pitch = 0
                                    roll = 0
                                }
                                // 延迟恢复陀螺仪
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    if !isDragging {
                                        startMotionUpdates()
                                    }
                                }
                            }
                    )
            }
            Spacer()
        }
        .padding(.top, 120)
        .padding(.bottom, 60)
        .onAppear { startMotionUpdates() }
        .onDisappear { stopMotionUpdates() }
    }

    // MARK: - Server Row

    @ViewBuilder
    private func serverRow(_ server: Server) -> some View {
        Button {
            connect(to: server)
        } label: {
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

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }

    // MARK: - Server Form Section

    private var serverFormSection: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
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

            // 扫码按钮
            Button {
                showScanner = true
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "qrcode.viewfinder")
                    Text("扫码输入")
                }
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.md)
            }
            .glassEffect(.regular.interactive(), in: .capsule)

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
        .padding(savedServers.isEmpty ? AppTheme.Spacing.lg : 0)
        .if(savedServers.isEmpty) { view in
            view.glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
        }
    }

    // MARK: - Motion

    private func startMotionUpdates() {
        let manager = CMMotionManager()
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let motion = motion, !isDragging else { return }
            withAnimation(.interactiveSpring(duration: 0.15)) {
                pitch = motion.attitude.pitch
                roll = motion.attitude.roll
            }
        }
        motionManager = manager
    }

    private func stopMotionUpdates() {
        motionManager?.stopDeviceMotionUpdates()
        motionManager = nil
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

    /// 连接服务器（先 health 检查，5秒超时）
    private func connect(to server: Server) {
        guard let apiService = APIService.create(for: server) else {
            errorMessage = "无效的服务器地址"
            return
        }

        isConnecting = true
        errorMessage = nil

        Task {
            let status = await connectWithTimeout(apiService: apiService, timeout: 5)

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
            let status = await connectWithTimeout(apiService: apiService, timeout: 5)

            await MainActor.run {
                isConnecting = false

                switch status {
                case .online:
                    LocalStorageService.shared.addServer(server)
                    LocalStorageService.shared.setCurrentServer(server.id)
                    LocalStorageService.shared.setLoggedIn(true)

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

    /// 带超时的连接检查
    private func connectWithTimeout(apiService: APIService, timeout: TimeInterval) async -> ServerStatus {
        await withTaskGroup(of: ServerStatus.self) { group in
            // 实际连接任务
            group.addTask {
                return await apiService.checkConnection()
            }

            // 超时任务
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return .checking
            }

            // 取第一个完成的结果
            let result = await group.next() ?? .offline
            group.cancelAll()
            return result
        }
    }

    private func deleteServer(_ server: Server) {
        withAnimation {
            LocalStorageService.shared.deleteServer(server.id)
            loadSavedServers()
        }
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
