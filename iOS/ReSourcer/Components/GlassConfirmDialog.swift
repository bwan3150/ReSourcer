//
//  GlassConfirmDialog.swift
//  ReSourcer
//
//  液态玻璃风格确认弹窗组件
//

import SwiftUI

// MARK: - Confirm Dialog 配置

/// 确认弹窗配置
struct GlassConfirmConfig {
    let title: String
    let message: String?
    let icon: String?
    let iconColor: Color
    let confirmTitle: String
    let confirmStyle: GlassButtonStyle
    let cancelTitle: String
    let showCancel: Bool

    init(
        title: String,
        message: String? = nil,
        icon: String? = nil,
        iconColor: Color = .white,
        confirmTitle: String = "确认",
        confirmStyle: GlassButtonStyle = .primary,
        cancelTitle: String = "取消",
        showCancel: Bool = true
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconColor = iconColor
        self.confirmTitle = confirmTitle
        self.confirmStyle = confirmStyle
        self.cancelTitle = cancelTitle
        self.showCancel = showCancel
    }

    // MARK: - 预设配置

    /// 删除确认
    static func delete(title: String = "确认删除？", message: String? = "此操作不可撤销") -> GlassConfirmConfig {
        GlassConfirmConfig(
            title: title,
            message: message,
            icon: "trash.fill",
            iconColor: .red,
            confirmTitle: "删除",
            confirmStyle: .destructive
        )
    }

    /// 退出确认
    static func exit(title: String = "确认退出？", message: String? = "未保存的更改将会丢失") -> GlassConfirmConfig {
        GlassConfirmConfig(
            title: title,
            message: message,
            icon: "rectangle.portrait.and.arrow.right",
            iconColor: .orange,
            confirmTitle: "退出",
            confirmStyle: .destructive
        )
    }

    /// 保存确认
    static func save(title: String = "保存更改？", message: String? = nil) -> GlassConfirmConfig {
        GlassConfirmConfig(
            title: title,
            message: message,
            icon: "checkmark.circle.fill",
            iconColor: .green,
            confirmTitle: "保存",
            confirmStyle: .primary
        )
    }

    /// 警告确认
    static func warning(title: String, message: String? = nil) -> GlassConfirmConfig {
        GlassConfirmConfig(
            title: title,
            message: message,
            icon: "exclamationmark.triangle.fill",
            iconColor: .orange,
            confirmTitle: "继续",
            confirmStyle: .primary
        )
    }
}

// MARK: - GlassConfirmDialog

/// 液态玻璃风格确认弹窗
struct GlassConfirmDialog: View {

    // MARK: - Properties

    let config: GlassConfirmConfig
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isVisible = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(isVisible ? 0.5 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    if config.showCancel {
                        dismiss(confirmed: false)
                    }
                }

            // 弹窗内容
            VStack(spacing: AppTheme.Spacing.lg) {
                // 图标
                if let icon = config.icon {
                    Image(systemName: icon)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(config.iconColor)
                        .symbolEffect(.bounce, value: isVisible)
                }

                // 标题
                Text(config.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                // 消息
                if let message = config.message {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 按钮区域
                buttonArea
                    .padding(.top, AppTheme.Spacing.sm)
            }
            .padding(AppTheme.Spacing.xxl)
            .frame(maxWidth: 300)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
            .scaleEffect(isVisible ? 1 : 0.85)
            .opacity(isVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(AppTheme.Animation.spring) {
                isVisible = true
            }
        }
    }

    // MARK: - Button Area

    @ViewBuilder
    private var buttonArea: some View {
        if config.showCancel {
            // 两个按钮：取消 + 确认
            HStack(spacing: AppTheme.Spacing.md) {
                GlassButton(config.cancelTitle, style: .secondary, size: .medium) {
                    dismiss(confirmed: false)
                }
                .frame(maxWidth: .infinity)

                GlassButton(config.confirmTitle, style: config.confirmStyle, size: .medium) {
                    dismiss(confirmed: true)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            // 单个确认按钮
            GlassButton(config.confirmTitle, style: config.confirmStyle, size: .medium) {
                dismiss(confirmed: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Methods

    private func dismiss(confirmed: Bool) {
        withAnimation(AppTheme.Animation.quick) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if confirmed {
                onConfirm()
            } else {
                onCancel()
            }
        }
    }
}

// MARK: - View Modifier

/// 确认弹窗 Modifier
struct GlassConfirmDialogModifier: ViewModifier {

    @Binding var isPresented: Bool
    let config: GlassConfirmConfig
    let onConfirm: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    GlassConfirmDialog(
                        config: config,
                        onConfirm: {
                            isPresented = false
                            onConfirm()
                        },
                        onCancel: {
                            isPresented = false
                            onCancel()
                        }
                    )
                    .transition(.opacity)
                }
            }
            .animation(AppTheme.Animation.quick, value: isPresented)
    }
}

// MARK: - View Extension

extension View {

    /// 添加确认弹窗
    func glassConfirmDialog(
        isPresented: Binding<Bool>,
        config: GlassConfirmConfig,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        modifier(GlassConfirmDialogModifier(
            isPresented: isPresented,
            config: config,
            onConfirm: onConfirm,
            onCancel: onCancel
        ))
    }

    /// 删除确认弹窗
    func glassDeleteConfirm(
        isPresented: Binding<Bool>,
        title: String = "确认删除？",
        message: String? = "此操作不可撤销",
        onConfirm: @escaping () -> Void
    ) -> some View {
        glassConfirmDialog(
            isPresented: isPresented,
            config: .delete(title: title, message: message),
            onConfirm: onConfirm
        )
    }

    /// 退出确认弹窗
    func glassExitConfirm(
        isPresented: Binding<Bool>,
        title: String = "确认退出？",
        message: String? = "未保存的更改将会丢失",
        onConfirm: @escaping () -> Void
    ) -> some View {
        glassConfirmDialog(
            isPresented: isPresented,
            config: .exit(title: title, message: message),
            onConfirm: onConfirm
        )
    }
}

// MARK: - Confirm Dialog Manager

/// 确认弹窗管理器（用于命令式调用）
@MainActor
@Observable
final class GlassConfirmManager {

    static let shared = GlassConfirmManager()

    private(set) var currentDialog: (config: GlassConfirmConfig, onConfirm: () -> Void, onCancel: () -> Void)?

    private init() {}

    /// 显示确认弹窗
    func show(
        config: GlassConfirmConfig,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        currentDialog = (config, onConfirm, onCancel)
    }

    /// 显示删除确认
    func showDelete(
        title: String = "确认删除？",
        message: String? = "此操作不可撤销",
        onConfirm: @escaping () -> Void
    ) {
        show(config: .delete(title: title, message: message), onConfirm: onConfirm)
    }

    /// 关闭弹窗
    func dismiss() {
        currentDialog = nil
    }
}

/// 确认弹窗容器视图
struct GlassConfirmContainer: View {

    @State private var manager = GlassConfirmManager.shared

    var body: some View {
        if let dialog = manager.currentDialog {
            GlassConfirmDialog(
                config: dialog.config,
                onConfirm: {
                    dialog.onConfirm()
                    manager.dismiss()
                },
                onCancel: {
                    dialog.onCancel()
                    manager.dismiss()
                }
            )
            .transition(.opacity)
        }
    }
}

// MARK: - Preview

#Preview("Glass Confirm Dialog") {
    struct PreviewWrapper: View {
        @State private var showDelete = false
        @State private var showExit = false
        @State private var showSave = false
        @State private var showWarning = false

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 16) {
                    Button("删除确认") { showDelete = true }
                    Button("退出确认") { showExit = true }
                    Button("保存确认") { showSave = true }
                    Button("警告确认") { showWarning = true }
                    Button("命令式调用") {
                        GlassConfirmManager.shared.showDelete(
                            title: "删除这个文件？",
                            message: "文件将被永久删除"
                        ) {
                            print("Confirmed delete")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .glassDeleteConfirm(isPresented: $showDelete) {
                print("Delete confirmed")
            }
            .glassExitConfirm(isPresented: $showExit) {
                print("Exit confirmed")
            }
            .glassConfirmDialog(
                isPresented: $showSave,
                config: .save(),
                onConfirm: { print("Save confirmed") }
            )
            .glassConfirmDialog(
                isPresented: $showWarning,
                config: .warning(title: "操作可能有风险", message: "确定要继续吗？"),
                onConfirm: { print("Warning confirmed") }
            )
            .overlay {
                GlassConfirmContainer()
            }
        }
    }

    return PreviewWrapper()
}
