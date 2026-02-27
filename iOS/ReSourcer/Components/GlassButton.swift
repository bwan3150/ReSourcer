//
//  GlassButton.swift
//  ReSourcer
//
//  液态玻璃风格按钮组件
//

import SwiftUI

// MARK: - 按钮样式枚举

/// 玻璃按钮样式
enum GlassButtonStyle {
    /// 主要按钮（实心玻璃）
    case primary
    /// 次要按钮（透明玻璃）
    case secondary
    /// 危险操作按钮（红色色调）
    case destructive
    /// 纯图标按钮
    case icon
    /// 文字按钮（无背景）
    case text
}

/// 玻璃按钮尺寸
enum GlassButtonSize {
    case small
    case medium
    case large

    var height: CGFloat {
        switch self {
        case .small: return 32
        case .medium: return 44
        case .large: return 56
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 16
        case .large: return 24
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .small: return 16
        case .medium: return 20
        case .large: return 24
        }
    }

    var font: Font {
        switch self {
        case .small: return .subheadline
        case .medium: return .body
        case .large: return .headline
        }
    }
}

// MARK: - GlassButton

/// 液态玻璃风格按钮
struct GlassButton: View {

    // MARK: - Properties

    let title: String?
    let icon: String?
    let style: GlassButtonStyle
    let size: GlassButtonSize
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void

    // MARK: - Initialization

    init(
        _ title: String,
        icon: String? = nil,
        style: GlassButtonStyle = .primary,
        size: GlassButtonSize = .medium,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.size = size
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    /// 纯图标按钮初始化
    init(
        icon: String,
        style: GlassButtonStyle = .icon,
        size: GlassButtonSize = .medium,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = nil
        self.icon = icon
        self.style = style
        self.size = size
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    // MARK: - Body

    var body: some View {
        Button(action: {
            if isEnabled && !isLoading {
                action()
            }
        }) {
            buttonContent
        }
        .disabled(!isEnabled || isLoading)
        .modifier(NativeButtonStyleModifier(style: style, size: size))
    }

    // MARK: - Content

    @ViewBuilder
    private var buttonContent: some View {
        if isLoading {
            ProgressView()
                .progressViewStyle(.circular)
        } else {
            HStack(spacing: AppTheme.Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                }
                if let title = title {
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

// MARK: - Native Button Style Modifier

/// 应用原生按钮样式 — iOS 26 自动液态玻璃，旧版标准系统样式
struct NativeButtonStyleModifier: ViewModifier {
    let style: GlassButtonStyle
    let size: GlassButtonSize

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .primary:
            content
                .buttonStyle(.borderedProminent)
                .controlSize(controlSize)

        case .secondary:
            content
                .buttonStyle(.bordered)
                .controlSize(controlSize)

        case .destructive:
            content
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(controlSize)

        case .icon:
            content
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(controlSize)

        case .text:
            content
                .buttonStyle(.borderless)
                .controlSize(controlSize)
        }
    }

    private var controlSize: ControlSize {
        switch size {
        case .small: .small
        case .medium: .regular
        case .large: .large
        }
    }
}

// MARK: - 便捷构造方法

extension GlassButton {

    /// 主要按钮
    static func primary(
        _ title: String,
        icon: String? = nil,
        size: GlassButtonSize = .medium,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> GlassButton {
        GlassButton(title, icon: icon, style: .primary, size: size, isLoading: isLoading, action: action)
    }

    /// 次要按钮
    static func secondary(
        _ title: String,
        icon: String? = nil,
        size: GlassButtonSize = .medium,
        action: @escaping () -> Void
    ) -> GlassButton {
        GlassButton(title, icon: icon, style: .secondary, size: size, action: action)
    }

    /// 危险操作按钮
    static func destructive(
        _ title: String,
        icon: String? = nil,
        size: GlassButtonSize = .medium,
        action: @escaping () -> Void
    ) -> GlassButton {
        GlassButton(title, icon: icon, style: .destructive, size: size, action: action)
    }

    /// 图标按钮
    static func icon(
        _ systemName: String,
        size: GlassButtonSize = .medium,
        action: @escaping () -> Void
    ) -> GlassButton {
        GlassButton(icon: systemName, style: .icon, size: size, action: action)
    }
}

// MARK: - Preview

#Preview("Glass Buttons") {
    ZStack {
        // 背景图片
        Image(systemName: "photo.artframe")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()

        VStack(spacing: 20) {
            // 主要按钮
            GlassButton.primary("确认", icon: "checkmark") {
                print("Primary tapped")
            }

            // 次要按钮
            GlassButton.secondary("取消") {
                print("Secondary tapped")
            }

            // 危险按钮
            GlassButton.destructive("删除", icon: "trash") {
                print("Destructive tapped")
            }

            // 图标按钮
            HStack(spacing: 16) {
                GlassButton.icon("heart.fill") {}
                GlassButton.icon("square.and.arrow.up") {}
                GlassButton.icon("ellipsis") {}
            }

            // 不同尺寸
            HStack(spacing: 12) {
                GlassButton("小", style: .primary, size: .small) {}
                GlassButton("中", style: .primary, size: .medium) {}
                GlassButton("大", style: .primary, size: .large) {}
            }

            // 加载状态
            GlassButton("加载中", style: .primary, isLoading: true) {}

            // 禁用状态
            GlassButton("禁用", style: .primary, isEnabled: false) {}
        }
        .padding()
    }
}
