//
//  GlassAlert.swift
//  ReSourcer
//
//  液态玻璃风格弹窗提示组件（Toast / Alert）
//

import SwiftUI

// MARK: - Alert 类型

/// 提示类型
enum GlassAlertType {
    case success
    case error
    case warning
    case info

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var tintColor: Color {
        .primary
    }
}

// MARK: - Alert 数据模型

/// 提示数据
struct GlassAlertData: Identifiable, Equatable {
    let id = UUID()
    let type: GlassAlertType
    let title: String
    let message: String?
    let duration: TimeInterval

    init(type: GlassAlertType, title: String, message: String? = nil, duration: TimeInterval = 3.0) {
        self.type = type
        self.title = title
        self.message = message
        self.duration = duration
    }

    static func == (lhs: GlassAlertData, rhs: GlassAlertData) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - GlassToast

/// 液态玻璃风格 Toast 提示（顶部/底部弹出）
struct GlassToast: View {

    let data: GlassAlertData
    let onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // 图标
            Image(systemName: data.type.icon)
                .font(.title2)
                .foregroundStyle(data.type.tintColor)

            // 文字内容
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(data.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if let message = data.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            // 关闭按钮
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(AppTheme.Spacing.xs)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .glassBackground(in: Capsule())
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 20)
        .onAppear {
            withAnimation(AppTheme.Animation.spring) {
                isVisible = true
            }
            // 自动消失
            DispatchQueue.main.asyncAfter(deadline: .now() + data.duration) {
                dismiss()
            }
        }
    }

    private func dismiss() {
        withAnimation(AppTheme.Animation.quick) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}

// MARK: - GlassAlertDialog

/// 液态玻璃风格居中弹窗
struct GlassAlertDialog: View {

    let data: GlassAlertData
    let primaryButton: AlertButton?
    let secondaryButton: AlertButton?
    let onDismiss: () -> Void

    @State private var isVisible = false

    struct AlertButton {
        let title: String
        let style: GlassButtonStyle
        let action: () -> Void

        init(_ title: String, style: GlassButtonStyle = .primary, action: @escaping () -> Void) {
            self.title = title
            self.style = style
            self.action = action
        }
    }

    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(isVisible ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // 弹窗内容
            VStack(spacing: AppTheme.Spacing.lg) {
                // 图标
                Image(systemName: data.type.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(data.type.tintColor)
                    .symbolEffect(.bounce, value: isVisible)

                // 标题
                Text(data.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                // 消息
                if let message = data.message {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 按钮
                HStack(spacing: AppTheme.Spacing.md) {
                    if let secondary = secondaryButton {
                        GlassButton(secondary.title, style: secondary.style, size: .medium) {
                            secondary.action()
                            dismiss()
                        }
                    }

                    if let primary = primaryButton {
                        GlassButton(primary.title, style: primary.style, size: .medium) {
                            primary.action()
                            dismiss()
                        }
                    } else {
                        GlassButton("确定", style: .primary, size: .medium) {
                            dismiss()
                        }
                    }
                }
                .padding(.top, AppTheme.Spacing.sm)
            }
            .padding(AppTheme.Spacing.xxl)
            .frame(maxWidth: 320)
            .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
            .scaleEffect(isVisible ? 1 : 0.9)
            .opacity(isVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(AppTheme.Animation.spring) {
                isVisible = true
            }
        }
    }

    private func dismiss() {
        withAnimation(AppTheme.Animation.quick) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}

// MARK: - Connection Failure Dialog

/// 连接失败对话框 - 用于在网络不通时提示用户切换地址
/// 每个备用地址的探测状态
private enum URLProbeState {
    case checking
    case reachable
    case unreachable
}

struct ConnectionFailureDialog: View {

    let failedURL: String
    let alternateURLs: [URL]
    let onSwitchURL: (URL) -> Void
    let onReturnToList: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible = false
    /// 各备用地址的探测状态，key 为 absoluteString
    @State private var probeStates: [String: URLProbeState] = [:]

    var body: some View {
        ZStack {
            // 背景遮罩（不可点击关闭，强制用户做出选择）
            Color.black.opacity(isVisible ? 0.5 : 0)
                .ignoresSafeArea()

            // 对话框内容
            VStack(spacing: AppTheme.Spacing.lg) {

                // 图标
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundStyle(.primary)
                    .symbolEffect(.bounce, value: isVisible)

                // 标题
                Text("连接失败")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                // 失败地址
                Text(failedURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Divider()
                    .padding(.horizontal, -AppTheme.Spacing.xxl)

                // 备用地址列表
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("切换到其他地址")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(alternateURLs, id: \.absoluteString) { url in
                        let probe = probeStates[url.absoluteString] ?? .checking
                        Button {
                            onSwitchURL(url)
                            dismiss()
                        } label: {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                // 探测状态图标
                                Group {
                                    switch probe {
                                    case .checking:
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .scaleEffect(0.75)
                                            .frame(width: 16, height: 16)
                                    case .reachable:
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    case .unreachable:
                                        Image(systemName: "xmark.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.subheadline)

                                Text(url.absoluteString)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 0)
                                if probe == .reachable {
                                    Text("可用")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.vertical, AppTheme.Spacing.sm)
                            .frame(maxWidth: .infinity)
                            .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
                        }
                        .disabled(probe == .unreachable)
                    }
                }

                // 返回服务器列表
                Button {
                    onReturnToList()
                    dismiss()
                } label: {
                    Text("返回服务器列表")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, AppTheme.Spacing.xs)
            }
            .padding(AppTheme.Spacing.xxl)
            .frame(maxWidth: 340)
            .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
            .scaleEffect(isVisible ? 1 : 0.9)
            .opacity(isVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(AppTheme.Animation.spring) {
                isVisible = true
            }
        }
        .task {
            await probeAllURLs()
        }
    }

    /// 并行探测所有备用地址，各自独立更新状态（哪个先回来就先刷新哪个）
    private func probeAllURLs() async {
        await withTaskGroup(of: (String, URLProbeState).self) { group in
            for url in alternateURLs {
                group.addTask {
                    let ok = await APIService.quickHealthCheck(url: url, timeout: 2)
                    return (url.absoluteString, ok ? .reachable : .unreachable)
                }
            }
            for await (key, state) in group {
                probeStates[key] = state
            }
        }
    }

    private func dismiss() {
        withAnimation(AppTheme.Animation.quick) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}

// MARK: - Alert Manager

/// 全局提示管理器
@MainActor
@Observable
final class GlassAlertManager {

    static let shared = GlassAlertManager()

    private(set) var toasts: [GlassAlertData] = []
    private(set) var currentAlert: (data: GlassAlertData, primary: GlassAlertDialog.AlertButton?, secondary: GlassAlertDialog.AlertButton?)?

    /// 连接失败对话框状态
    struct ConnectionFailureState {
        let failedURL: String
        let alternateURLs: [URL]
        let onSwitchURL: (URL) -> Void
        let onReturnToList: () -> Void
    }
    private(set) var connectionFailure: ConnectionFailureState?

    /// Quick Loading 状态
    private(set) var isQuickLoading = false
    private var quickLoadingStart: ContinuousClock.Instant?
    /// 最小显示时长
    private let quickLoadingMinDuration: Duration = .milliseconds(600)

    private init() {}

    // MARK: - Toast Methods

    /// 显示成功提示
    func showSuccess(_ title: String, message: String? = nil) {
        showToast(.init(type: .success, title: title, message: message))
    }

    /// 显示错误提示
    func showError(_ title: String, message: String? = nil) {
        showToast(.init(type: .error, title: title, message: message))
    }

    /// 显示警告提示
    func showWarning(_ title: String, message: String? = nil) {
        showToast(.init(type: .warning, title: title, message: message))
    }

    /// 显示信息提示
    func showInfo(_ title: String, message: String? = nil) {
        showToast(.init(type: .info, title: title, message: message))
    }

    /// 显示 Toast
    func showToast(_ data: GlassAlertData) {
        toasts.append(data)
    }

    /// 移除 Toast
    func removeToast(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    // MARK: - Alert Methods

    /// 显示弹窗
    func showAlert(
        type: GlassAlertType,
        title: String,
        message: String? = nil,
        primaryButton: GlassAlertDialog.AlertButton? = nil,
        secondaryButton: GlassAlertDialog.AlertButton? = nil
    ) {
        let data = GlassAlertData(type: type, title: title, message: message)
        currentAlert = (data, primaryButton, secondaryButton)
    }

    /// 关闭弹窗
    func dismissAlert() {
        currentAlert = nil
    }

    // MARK: - Connection Failure

    /// 显示连接失败切换对话框（已有对话框时忽略，避免重复弹出）
    func showConnectionFailure(
        failedURL: String,
        alternateURLs: [URL],
        onSwitchURL: @escaping (URL) -> Void,
        onReturnToList: @escaping () -> Void
    ) {
        guard connectionFailure == nil else { return }
        connectionFailure = ConnectionFailureState(
            failedURL: failedURL,
            alternateURLs: alternateURLs,
            onSwitchURL: onSwitchURL,
            onReturnToList: onReturnToList
        )
    }

    /// 关闭连接失败对话框
    func dismissConnectionFailure() {
        connectionFailure = nil
    }

    // MARK: - Quick Loading

    /// 显示快速加载指示器
    func showQuickLoading() {
        quickLoadingStart = .now
        withAnimation(AppTheme.Animation.quick) {
            isQuickLoading = true
        }
    }

    /// 隐藏快速加载指示器（保证最小显示时长）
    func hideQuickLoading() {
        Task { @MainActor in
            // 确保至少显示 minDuration
            if let start = quickLoadingStart {
                let elapsed = ContinuousClock.now - start
                if elapsed < quickLoadingMinDuration {
                    try? await Task.sleep(for: quickLoadingMinDuration - elapsed)
                }
            }
            withAnimation(AppTheme.Animation.quick) {
                isQuickLoading = false
            }
            quickLoadingStart = nil
        }
    }

    /// 便捷方法：在异步操作期间自动显示/隐藏加载指示器
    func withQuickLoading<T>(_ operation: @escaping () async throws -> T) async rethrows -> T {
        showQuickLoading()
        defer { hideQuickLoading() }
        return try await operation()
    }
}

// MARK: - Toast Container View

/// Toast 容器视图（放在根视图）
struct GlassToastContainer: View {

    @State private var alertManager = GlassAlertManager.shared

    var body: some View {
        VStack {
            Spacer()

            // 底部 Toast 列表
            VStack(spacing: AppTheme.Spacing.sm) {
                ForEach(alertManager.toasts) { toast in
                    GlassToast(data: toast) {
                        alertManager.removeToast(toast.id)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, 72)
            .animation(AppTheme.Animation.spring, value: alertManager.toasts.count)
        }
    }
}

// MARK: - Alert Container View

/// Alert 弹窗容器视图
struct GlassAlertContainer: View {

    @State private var alertManager = GlassAlertManager.shared

    var body: some View {
        if let alert = alertManager.currentAlert {
            GlassAlertDialog(
                data: alert.data,
                primaryButton: alert.primary,
                secondaryButton: alert.secondary
            ) {
                alertManager.dismissAlert()
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Quick Loading View

/// 快速加载指示器 — 居中浮动的液态玻璃小弹窗，仅动画无文字
struct GlassQuickLoadingView: View {

    @State private var animating = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.primary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.0 : 0.3)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: animating
                    )
            }
        }
        .padding(AppTheme.Spacing.lg)
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
        .onAppear { animating = true }
    }
}

// MARK: - Connection Failure Container

/// 连接失败对话框容器视图
struct ConnectionFailureContainer: View {

    @State private var alertManager = GlassAlertManager.shared

    var body: some View {
        if let state = alertManager.connectionFailure {
            ConnectionFailureDialog(
                failedURL: state.failedURL,
                alternateURLs: state.alternateURLs,
                onSwitchURL: state.onSwitchURL,
                onReturnToList: state.onReturnToList
            ) {
                alertManager.dismissConnectionFailure()
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Quick Loading Container

/// Quick Loading 容器视图
struct GlassQuickLoadingContainer: View {

    @State private var alertManager = GlassAlertManager.shared

    var body: some View {
        if alertManager.isQuickLoading {
            GlassQuickLoadingView()
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }
}

// MARK: - View Extension

extension View {
    /// 添加全局 Toast、Alert、Quick Loading 和连接失败对话框支持
    func withGlassAlerts() -> some View {
        self
            .overlay(alignment: .bottom) {
                GlassToastContainer()
            }
            .overlay {
                GlassAlertContainer()
            }
            .overlay {
                ConnectionFailureContainer()
            }
            .overlay {
                GlassQuickLoadingContainer()
            }
    }
}

// MARK: - Preview

#Preview("Glass Toast") {
    struct PreviewWrapper: View {
        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [.gray.opacity(0.2), .gray.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 16) {
                    Button("Success Toast") {
                        GlassAlertManager.shared.showSuccess("操作成功", message: "文件已保存")
                    }
                    Button("Error Toast") {
                        GlassAlertManager.shared.showError("操作失败", message: "网络连接超时")
                    }
                    Button("Warning Toast") {
                        GlassAlertManager.shared.showWarning("注意", message: "存储空间不足")
                    }
                    Button("Info Toast") {
                        GlassAlertManager.shared.showInfo("提示", message: "新版本可用")
                    }
                    Button("Show Alert") {
                        GlassAlertManager.shared.showAlert(
                            type: .warning,
                            title: "确认删除？",
                            message: "此操作不可撤销",
                            primaryButton: .init("删除", style: .destructive) {
                                print("Deleted")
                            },
                            secondaryButton: .init("取消", style: .secondary) {
                                print("Cancelled")
                            }
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .withGlassAlerts()
        }
    }

    return PreviewWrapper()
}
