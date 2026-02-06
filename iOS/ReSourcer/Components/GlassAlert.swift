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
        .glassEffect(.regular, in: .capsule)
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
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
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

// MARK: - Alert Manager

/// 全局提示管理器
@MainActor
@Observable
final class GlassAlertManager {

    static let shared = GlassAlertManager()

    private(set) var toasts: [GlassAlertData] = []
    private(set) var currentAlert: (data: GlassAlertData, primary: GlassAlertDialog.AlertButton?, secondary: GlassAlertDialog.AlertButton?)?

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

// MARK: - View Extension

extension View {
    /// 添加全局 Toast 和 Alert 支持
    func withGlassAlerts() -> some View {
        self
            .overlay(alignment: .bottom) {
                GlassToastContainer()
            }
            .overlay {
                GlassAlertContainer()
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
