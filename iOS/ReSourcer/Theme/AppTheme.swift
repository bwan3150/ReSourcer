//
//  AppTheme.swift
//  ReSourcer
//
//  应用主题配置 - 统一管理颜色、字体、间距等设计元素
//

import SwiftUI

// MARK: - 应用主题

/// 应用主题命名空间
enum AppTheme {

    // MARK: - 颜色

    enum Colors {
        /// 主色调（黑白灰风格，跟随系统明暗）
        static let primary = Color.primary

        /// 成功色
        static let success = Color.green

        /// 警告色
        static let warning = Color.orange

        /// 错误色
        static let error = Color.red

        /// 信息色
        static let info = Color.gray

        /// 文本颜色
        enum Text {
            static let primary = Color.primary
            static let secondary = Color.secondary
            static let tertiary = Color(uiColor: .tertiaryLabel)
            static let onGlass = Color.white
        }

        /// 背景颜色
        enum Background {
            static let primary = Color(uiColor: .systemBackground)
            static let secondary = Color(uiColor: .secondarySystemBackground)
            static let tertiary = Color(uiColor: .tertiarySystemBackground)
            static let grouped = Color(uiColor: .systemGroupedBackground)
        }
    }

    // MARK: - 间距

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: - 圆角

    enum CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        /// 用于 Bottom Sheet 等大组件
        static let sheet: CGFloat = 28
    }

    // MARK: - 字体

    enum Fonts {
        static let largeTitle = Font.largeTitle
        static let title = Font.title
        static let title2 = Font.title2
        static let title3 = Font.title3
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2
    }

    // MARK: - 图标尺寸

    enum IconSize {
        static let sm: CGFloat = 16
        static let md: CGFloat = 20
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 44
    }

    // MARK: - 动画

    enum Animation {
        static let quick = SwiftUI.Animation.easeOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.75)
        static let bouncy = SwiftUI.Animation.bouncy(duration: 0.4)
    }

    // MARK: - 阴影

    enum Shadow {
        static let sm = ShadowStyle(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        static let md = ShadowStyle(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        static let lg = ShadowStyle(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
    }

    // MARK: - TabBar 配置

    enum TabBar {
        static let height: CGFloat = 49
        static let iconSize: CGFloat = 24
        static let labelFont = Font.caption2
        static let bottomPadding: CGFloat = 34 // Safe area
    }

    // MARK: - Bottom Sheet 配置

    enum BottomSheet {
        static let handleWidth: CGFloat = 36
        static let handleHeight: CGFloat = 5
        static let headerHeight: CGFloat = 56
        static let maxHeightRatio: CGFloat = 0.9
    }
}

// MARK: - Shadow Style

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Extension for Shadow

extension View {
    func shadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
