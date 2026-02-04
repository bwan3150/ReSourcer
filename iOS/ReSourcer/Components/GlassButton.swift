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
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }

    // MARK: - Content

    @ViewBuilder
    private var buttonContent: some View {
        Group {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(foregroundColor)
            } else {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: size.iconSize, weight: .medium))
                    }
                    if let title = title {
                        Text(title)
                            .font(size.font.weight(.medium))
                    }
                }
            }
        }
        .foregroundStyle(foregroundColor)
        .frame(height: size.height)
        .frame(minWidth: style == .icon ? size.height : nil)
        .padding(.horizontal, style == .icon ? 0 : size.horizontalPadding)
        .modifier(GlassButtonStyleModifier(style: style, isEnabled: isEnabled))
    }

    // MARK: - Computed Properties

    private var foregroundColor: Color {
        guard isEnabled else {
            return .secondary
        }
        switch style {
        case .primary, .icon:
            return .white
        case .secondary:
            return .primary
        case .destructive:
            return .white
        case .text:
            return AppTheme.Colors.primary
        }
    }
}

// MARK: - Glass Button Style Modifier

/// 应用玻璃效果的 ViewModifier
struct GlassButtonStyleModifier: ViewModifier {
    let style: GlassButtonStyle
    let isEnabled: Bool

    func body(content: Content) -> some View {
        switch style {
        case .primary:
            content
                .glassEffect(.regular.interactive(), in: .capsule)
                .opacity(isEnabled ? 1.0 : 0.5)

        case .secondary:
            content
                .glassEffect(.clear.interactive(), in: .capsule)
                .opacity(isEnabled ? 1.0 : 0.5)

        case .destructive:
            content
                .glassEffect(.regular.tint(.red).interactive(), in: .capsule)
                .opacity(isEnabled ? 1.0 : 0.5)

        case .icon:
            content
                .glassEffect(.regular.interactive(), in: .circle)
                .opacity(isEnabled ? 1.0 : 0.5)

        case .text:
            content
                .contentShape(Capsule())
                .opacity(isEnabled ? 1.0 : 0.5)
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
