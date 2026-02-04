//
//  GlassNavigationBar.swift
//  ReSourcer
//
//  液态玻璃风格顶部导航栏
//

import SwiftUI

// MARK: - GlassNavigationBar

/// 液态玻璃风格顶部导航栏
struct GlassNavigationBar<Leading: View, Trailing: View>: View {

    // MARK: - Properties

    let title: String
    let subtitle: String?
    let largeTitle: Bool
    let leading: () -> Leading
    let trailing: () -> Trailing

    // MARK: - Initialization

    init(
        title: String,
        subtitle: String? = nil,
        largeTitle: Bool = false,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.largeTitle = largeTitle
        self.leading = leading
        self.trailing = trailing
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if largeTitle {
                largeTitleLayout
            } else {
                inlineTitleLayout
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.sm)
        .glassEffect(.regular, in: UnevenRoundedRectangle(
            bottomLeadingRadius: AppTheme.CornerRadius.xl,
            bottomTrailingRadius: AppTheme.CornerRadius.xl
        ))
    }

    // MARK: - Inline Title Layout

    private var inlineTitleLayout: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // 左侧按钮
            leading()
                .frame(minWidth: 44)

            Spacer()

            // 标题
            VStack(spacing: 0) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            // 右侧按钮
            trailing()
                .frame(minWidth: 44)
        }
        .frame(height: 44)
        .padding(.top, AppTheme.Spacing.sm)
    }

    // MARK: - Large Title Layout

    private var largeTitleLayout: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // 顶部工具栏
            HStack {
                leading()
                Spacer()
                trailing()
            }
            .frame(height: 44)

            // 大标题
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.bottom, AppTheme.Spacing.sm)
        }
        .padding(.top, AppTheme.Spacing.sm)
    }
}

// MARK: - Navigation Bar Button

/// 导航栏按钮
struct GlassNavBarButton: View {

    let icon: String
    let badge: Int?
    let action: () -> Void

    init(_ icon: String, badge: Int? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.badge = badge
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if let badge = badge, badge > 0 {
                        GlassBadge(badge)
                            .offset(x: 8, y: -4)
                    }
                }
        }
    }
}

/// 导航栏返回按钮
struct GlassBackButton: View {

    let title: String?
    let action: () -> Void

    init(_ title: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xxs) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))

                if let title = title {
                    Text(title)
                        .font(.body)
                }
            }
            .foregroundStyle(.white)
        }
    }
}

// MARK: - GlassNavigationView

/// 带玻璃导航栏的页面容器
struct GlassNavigationView<Content: View, Leading: View, Trailing: View>: View {

    let title: String
    let subtitle: String?
    let largeTitle: Bool
    let leading: () -> Leading
    let trailing: () -> Trailing
    let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        largeTitle: Bool = false,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.largeTitle = largeTitle
        self.leading = leading
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            // 导航栏
            GlassNavigationBar(
                title: title,
                subtitle: subtitle,
                largeTitle: largeTitle,
                leading: leading,
                trailing: trailing
            )

            // 内容区域
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Scrollable Navigation View

/// 带滚动响应的玻璃导航栏页面
struct GlassScrollableNavigationView<Content: View, Leading: View, Trailing: View>: View {

    let title: String
    let subtitle: String?
    let leading: () -> Leading
    let trailing: () -> Trailing
    let content: () -> Content

    @State private var scrollOffset: CGFloat = 0
    @State private var showLargeTitle = true

    private let largeTitleThreshold: CGFloat = 50

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            // 导航栏（根据滚动切换样式）
            GlassNavigationBar(
                title: title,
                subtitle: showLargeTitle ? subtitle : nil,
                largeTitle: showLargeTitle,
                leading: leading,
                trailing: trailing
            )
            .animation(AppTheme.Animation.quick, value: showLargeTitle)

            // 内容区域
            ScrollView {
                content()
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geometry.frame(in: .named("scroll")).minY
                                )
                        }
                    )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
                withAnimation(AppTheme.Animation.quick) {
                    showLargeTitle = value > -largeTitleThreshold
                }
            }
        }
    }
}

// MARK: - Preference Key

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Preview

#Preview("Glass Navigation Bar") {
    struct PreviewWrapper: View {
        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 40) {
                    // 内联标题
                    GlassNavigationBar(
                        title: "标题",
                        subtitle: "副标题",
                        leading: {
                            GlassBackButton("返回") {}
                        },
                        trailing: {
                            GlassNavBarButton("ellipsis", badge: 3) {}
                        }
                    )

                    // 大标题
                    GlassNavigationBar(
                        title: "大标题",
                        subtitle: "这是副标题描述",
                        largeTitle: true,
                        leading: {
                            GlassBackButton {}
                        },
                        trailing: {
                            HStack(spacing: 8) {
                                GlassNavBarButton("magnifyingglass") {}
                                GlassNavBarButton("plus") {}
                            }
                        }
                    )

                    Spacer()
                }
            }
        }
    }

    return PreviewWrapper()
}

#Preview("Glass Navigation View") {
    GlassScrollableNavigationView(
        title: "画廊",
        subtitle: "共 128 个文件",
        leading: {
            GlassNavBarButton("sidebar.leading") {}
        },
        trailing: {
            GlassNavBarButton("ellipsis") {}
        }
    ) {
        LazyVStack(spacing: 12) {
            ForEach(0..<30) { index in
                HStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 60, height: 60)

                    VStack(alignment: .leading) {
                        Text("项目 \(index + 1)")
                            .foregroundStyle(.white)
                        Text("描述信息")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding()
    }
    .previewWithGlassBackground()
}
