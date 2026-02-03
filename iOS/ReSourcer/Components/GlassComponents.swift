//
//  GlassComponents.swift
//  ReSourcer
//
//  其他液态玻璃风格通用组件
//

import SwiftUI

// MARK: - GlassSearchBar

/// 液态玻璃风格搜索框
struct GlassSearchBar: View {

    @Binding var text: String
    let placeholder: String
    let onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool

    init(
        text: Binding<String>,
        placeholder: String = "搜索",
        onSubmit: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .tint(.white)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit {
                    onSubmit?()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.md)
        .glassEffect(.clear, in: .capsule)
    }
}

// MARK: - GlassTextField

/// 液态玻璃风格输入框
struct GlassTextField: View {

    let title: String
    @Binding var text: String
    let placeholder: String
    let icon: String?
    let isSecure: Bool
    let errorMessage: String?

    init(
        _ title: String = "",
        text: Binding<String>,
        placeholder: String = "",
        icon: String? = nil,
        isSecure: Bool = false,
        errorMessage: String? = nil
    ) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.icon = icon
        self.isSecure = isSecure
        self.errorMessage = errorMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            // 标题
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }

            // 输入区域
            HStack(spacing: AppTheme.Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .tint(.white)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.md)
            .glassEffect(
                errorMessage != nil ? .regular.tint(.red.opacity(0.3)) : .clear,
                in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
            )

            // 错误消息
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - GlassCard

/// 液态玻璃风格卡片
struct GlassCard<Content: View>: View {

    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(AppTheme.Spacing.lg)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }
}

// MARK: - GlassListRow

/// 液态玻璃风格列表行
struct GlassListRow<Leading: View, Trailing: View>: View {

    let title: String
    let subtitle: String?
    let leading: () -> Leading
    let trailing: () -> Trailing
    let action: (() -> Void)?

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.trailing = trailing
        self.action = action
    }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                leading()

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.white)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                trailing()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md))
    }
}

// MARK: - GlassLoadingView

/// 液态玻璃风格加载视图
struct GlassLoadingView: View {

    let message: String?

    init(_ message: String? = nil) {
        self.message = message
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(.white)

            if let message = message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }
}

// MARK: - GlassLoadingOverlay

/// 全屏加载遮罩
struct GlassLoadingOverlay: View {

    let isLoading: Bool
    let message: String?

    init(isLoading: Bool, message: String? = "加载中...") {
        self.isLoading = isLoading
        self.message = message
    }

    var body: some View {
        if isLoading {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                GlassLoadingView(message)
            }
            .transition(.opacity)
        }
    }
}

// MARK: - GlassEmptyView

/// 液态玻璃风格空状态视图
struct GlassEmptyView: View {

    let icon: String
    let title: String
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String = "tray",
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.5))

            VStack(spacing: AppTheme.Spacing.xs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                if let message = message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }

            if let actionTitle = actionTitle, let action = action {
                GlassButton.primary(actionTitle, size: .medium, action: action)
            }
        }
        .padding(AppTheme.Spacing.xxl)
    }
}

// MARK: - GlassSegmentedControl

/// 液态玻璃风格分段控制器
struct GlassSegmentedControl<T: Hashable>: View {

    @Binding var selection: T
    let items: [(value: T, label: String)]

    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(items, id: \.value) { item in
                    segmentButton(for: item)
                }
            }
            .padding(AppTheme.Spacing.xs)
            .glassEffect(.clear, in: .capsule)
        }
    }

    @ViewBuilder
    private func segmentButton(for item: (value: T, label: String)) -> some View {
        let isSelected = selection == item.value

        Button {
            withAnimation(AppTheme.Animation.bouncy) {
                selection = item.value
            }
        } label: {
            Text(item.label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .glassEffect(isSelected ? .regular : .identity, in: .capsule)
                .glassEffectID(item.value.hashValue, in: namespace)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GlassBadge

/// 液态玻璃风格徽章
struct GlassBadge: View {

    let count: Int
    let maxCount: Int

    init(_ count: Int, max maxCount: Int = 99) {
        self.count = count
        self.maxCount = maxCount
    }

    var body: some View {
        if count > 0 {
            Text(count > maxCount ? "\(maxCount)+" : "\(count)")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xxs)
                .glassEffect(.regular.tint(.red), in: .capsule)
        }
    }
}

// MARK: - GlassChip

/// 液态玻璃风格标签/芯片
struct GlassChip: View {

    let label: String
    let icon: String?
    let isSelected: Bool
    let onTap: () -> Void

    init(_ label: String, icon: String? = nil, isSelected: Bool = false, onTap: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.isSelected = isSelected
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                Text(label)
                    .font(.subheadline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .glassEffect(isSelected ? .regular : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View Modifier for Loading

extension View {

    /// 添加加载遮罩
    func glassLoading(isLoading: Bool, message: String? = "加载中...") -> some View {
        self.overlay {
            GlassLoadingOverlay(isLoading: isLoading, message: message)
                .animation(AppTheme.Animation.quick, value: isLoading)
        }
    }
}

// MARK: - Preview

#Preview("Glass Components") {
    struct PreviewWrapper: View {
        @State private var searchText = ""
        @State private var username = ""
        @State private var password = ""
        @State private var selectedSegment = 0
        @State private var isLoading = false

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 搜索框
                        GlassSearchBar(text: $searchText, placeholder: "搜索文件...")

                        // 输入框
                        GlassTextField("用户名", text: $username, placeholder: "请输入用户名", icon: "person")
                        GlassTextField("密码", text: $password, placeholder: "请输入密码", icon: "lock", isSecure: true)

                        // 分段控制器
                        GlassSegmentedControl(selection: $selectedSegment, items: [
                            (0, "全部"),
                            (1, "图片"),
                            (2, "视频")
                        ])

                        // 卡片
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("这是一个卡片")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text("卡片内容描述")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }

                        // 列表行
                        GlassListRow(
                            title: "设置项",
                            subtitle: "点击查看详情",
                            leading: {
                                Image(systemName: "gear")
                                    .foregroundStyle(.white)
                            },
                            trailing: {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        )

                        // 标签
                        HStack {
                            GlassChip("标签1", isSelected: true) {}
                            GlassChip("标签2", icon: "star") {}
                            GlassBadge(5)
                        }

                        // 加载视图
                        GlassLoadingView("正在加载...")

                        // 空状态
                        GlassEmptyView(
                            icon: "photo.on.rectangle.angled",
                            title: "暂无内容",
                            message: "点击下方按钮添加内容",
                            actionTitle: "添加"
                        ) {}

                        // 加载按钮
                        GlassButton("触发加载", style: .primary) {
                            isLoading = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                isLoading = false
                            }
                        }
                    }
                    .padding()
                }
            }
            .glassLoading(isLoading: isLoading)
        }
    }

    return PreviewWrapper()
}
