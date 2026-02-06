//
//  GlassTabBar.swift
//  ReSourcer
//
//  液态玻璃风格底部导航栏
//

import SwiftUI

// MARK: - Tab Item 协议

/// Tab 项目协议
protocol GlassTabItem: Hashable, CaseIterable {
    var title: String { get }
    var icon: String { get }
    var selectedIcon: String { get }
}

// MARK: - 默认实现

extension GlassTabItem {
    /// 默认选中图标与普通图标相同
    var selectedIcon: String { icon }
}

// MARK: - GlassTabBar

/// 液态玻璃风格底部导航栏
struct GlassTabBar<Tab: GlassTabItem>: View {

    // MARK: - Properties

    @Binding var selectedTab: Tab
    let tabs: [Tab]

    /// 用于玻璃效果形变的命名空间
    @Namespace private var namespace

    // MARK: - Initialization

    init(selection: Binding<Tab>, tabs: [Tab]? = nil) {
        self._selectedTab = selection
        self.tabs = tabs ?? Array(Tab.allCases)
    }

    // MARK: - Body

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.sm)
    }

    // MARK: - Tab Button

    @ViewBuilder
    private func tabButton(for tab: Tab) -> some View {
        let isSelected = selectedTab == tab

        Button {
            withAnimation(AppTheme.Animation.bouncy) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: AppTheme.TabBar.iconSize, weight: isSelected ? .semibold : .regular))
                    .symbolEffect(.bounce, value: isSelected)

                Text(tab.title)
                    .font(AppTheme.TabBar.labelFont)
                    .fontWeight(isSelected ? .medium : .regular)
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GlassTabView

/// 带玻璃导航栏的 TabView 容器
struct GlassTabView<Tab: GlassTabItem, Content: View>: View {

    // MARK: - Properties

    @Binding var selectedTab: Tab
    let tabs: [Tab]
    let content: (Tab) -> Content

    // MARK: - Initialization

    init(
        selection: Binding<Tab>,
        tabs: [Tab]? = nil,
        @ViewBuilder content: @escaping (Tab) -> Content
    ) {
        self._selectedTab = selection
        self.tabs = tabs ?? Array(Tab.allCases)
        self.content = content
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // 内容区域
            TabView(selection: $selectedTab) {
                ForEach(tabs, id: \.self) { tab in
                    content(tab)
                        .tag(tab)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // 玻璃导航栏
            GlassTabBar(selection: $selectedTab, tabs: tabs)
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - 浮动样式 TabBar

/// 浮动居中的玻璃导航栏（适用于少量 Tab）
struct GlassFloatingTabBar<Tab: GlassTabItem>: View {

    @Binding var selectedTab: Tab
    let tabs: [Tab]

    @Namespace private var namespace

    init(selection: Binding<Tab>, tabs: [Tab]? = nil) {
        self._selectedTab = selection
        self.tabs = tabs ?? Array(Tab.allCases)
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: AppTheme.Spacing.xs) {
                ForEach(tabs, id: \.self) { tab in
                    floatingTabButton(for: tab)
                }
            }
            .padding(AppTheme.Spacing.xs)
            .glassEffect(.regular, in: .capsule)
        }
    }

    @ViewBuilder
    private func floatingTabButton(for tab: Tab) -> some View {
        let isSelected = selectedTab == tab

        Button {
            withAnimation(AppTheme.Animation.bouncy) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 18, weight: .medium))

                if isSelected {
                    Text(tab.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, isSelected ? AppTheme.Spacing.lg : AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.md)
            .glassEffect(
                isSelected ? .regular.interactive() : .clear,
                in: .capsule
            )
            .glassEffectID(tab.hashValue, in: namespace)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 示例 Tab 枚举

/// 示例：主要 Tab 项
enum MainTab: String, GlassTabItem, CaseIterable {
    case classifier
    case gallery
    case download
    case settings

    var title: String {
        switch self {
        case .classifier: return "分类"
        case .gallery: return "画廊"
        case .download: return "下载"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .classifier: return "square.grid.2x2"
        case .gallery: return "photo.on.rectangle"
        case .download: return "arrow.down.circle"
        case .settings: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .classifier: return "square.grid.2x2.fill"
        case .gallery: return "photo.on.rectangle.fill"
        case .download: return "arrow.down.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Preview

#Preview("Glass TabBar") {
    struct PreviewWrapper: View {
        @State private var selectedTab: MainTab = .classifier

        var body: some View {
            ZStack {
                // 模拟内容背景
                LinearGradient(
                    colors: [.gray.opacity(0.2), .gray.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack {
                    Spacer()

                    Text("当前: \(selectedTab.title)")
                        .font(.title)
                        .foregroundStyle(.primary)

                    Spacer()

                    // 标准 TabBar
                    GlassTabBar(selection: $selectedTab)

                    Spacer().frame(height: 40)

                    // 浮动 TabBar
                    GlassFloatingTabBar(selection: $selectedTab)

                    Spacer().frame(height: 40)
                }
            }
        }
    }

    return PreviewWrapper()
}

#Preview("Glass TabView") {
    struct PreviewWrapper: View {
        @State private var selectedTab: MainTab = .classifier

        var body: some View {
            GlassTabView(selection: $selectedTab) { tab in
                ZStack {
                    LinearGradient(
                        colors: [.gray.opacity(0.15), .gray.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    Text(tab.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
            }
        }
    }

    return PreviewWrapper()
}
