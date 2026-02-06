//
//  GlassBottomSheet.swift
//  ReSourcer
//
//  液态玻璃风格底部抽屉组件
//

import SwiftUI

// MARK: - Bottom Sheet 高度

/// 底部抽屉高度配置
enum GlassBottomSheetHeight {
    /// 固定高度
    case fixed(CGFloat)
    /// 屏幕比例
    case ratio(CGFloat)
    /// 自适应内容高度
    case fit
    /// 全屏
    case fullScreen

    func resolve(in geometry: GeometryProxy) -> CGFloat {
        switch self {
        case .fixed(let height):
            return height
        case .ratio(let ratio):
            return geometry.size.height * min(ratio, AppTheme.BottomSheet.maxHeightRatio)
        case .fit:
            return geometry.size.height * 0.5 // 将由内容决定
        case .fullScreen:
            return geometry.size.height * AppTheme.BottomSheet.maxHeightRatio
        }
    }
}

// MARK: - GlassBottomSheet

/// 液态玻璃风格底部抽屉
struct GlassBottomSheet<Content: View>: View {

    // MARK: - Properties

    @Binding var isPresented: Bool
    let height: GlassBottomSheetHeight
    let showHandle: Bool
    let title: String?
    let showCloseButton: Bool
    let onDismiss: (() -> Void)?
    let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    // MARK: - Initialization

    init(
        isPresented: Binding<Bool>,
        height: GlassBottomSheetHeight = .fit,
        showHandle: Bool = true,
        title: String? = nil,
        showCloseButton: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self.height = height
        self.showHandle = showHandle
        self.title = title
        self.showCloseButton = showCloseButton
        self.onDismiss = onDismiss
        self.content = content
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // 背景遮罩
                if isPresented {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            dismiss()
                        }
                        .transition(.opacity)
                }

                // 底部抽屉
                if isPresented {
                    sheetContent(in: geometry)
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(AppTheme.Animation.spring, value: isPresented)
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(in geometry: GeometryProxy) -> some View {
        let sheetHeight = calculateHeight(in: geometry)

        VStack(spacing: 0) {
            // 拖拽手柄
            if showHandle {
                handle
            }

            // 标题栏
            if title != nil || showCloseButton {
                headerBar
            }

            // 内容区域
            ScrollView {
                content()
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + AppTheme.Spacing.lg)
                    .background(
                        GeometryReader { contentGeometry in
                            Color.clear.preference(
                                key: ContentHeightPreferenceKey.self,
                                value: contentGeometry.size.height
                            )
                        }
                    )
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxHeight: sheetHeight)
        .glassEffect(.regular, in: UnevenRoundedRectangle(
            topLeadingRadius: AppTheme.CornerRadius.sheet,
            topTrailingRadius: AppTheme.CornerRadius.sheet
        ))
        .offset(y: max(0, offset + dragOffset))
        .gesture(dragGesture(sheetHeight: sheetHeight))
        .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
            contentHeight = height
        }
    }

    // MARK: - Handle

    private var handle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.white.opacity(0.4))
            .frame(width: AppTheme.BottomSheet.handleWidth, height: AppTheme.BottomSheet.handleHeight)
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.xs)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            // 左侧占位
            if showCloseButton {
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer()

            // 标题
            if let title = title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Spacer()

            // 关闭按钮
            if showCloseButton {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .frame(height: AppTheme.BottomSheet.headerHeight)
        .padding(.horizontal, AppTheme.Spacing.sm)
    }

    // MARK: - Calculations

    private func calculateHeight(in geometry: GeometryProxy) -> CGFloat {
        switch height {
        case .fit:
            let calculatedHeight = contentHeight + AppTheme.BottomSheet.headerHeight + 40
            let maxHeight = geometry.size.height * AppTheme.BottomSheet.maxHeightRatio
            return min(calculatedHeight, maxHeight)
        default:
            return height.resolve(in: geometry)
        }
    }

    // MARK: - Gestures

    private func dragGesture(sheetHeight: CGFloat) -> some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                if value.translation.height > 0 {
                    state = value.translation.height
                }
            }
            .onEnded { value in
                let threshold = sheetHeight * 0.25
                if value.translation.height > threshold {
                    dismiss()
                } else {
                    withAnimation(AppTheme.Animation.spring) {
                        offset = 0
                    }
                }
            }
    }

    // MARK: - Methods

    private func dismiss() {
        withAnimation(AppTheme.Animation.spring) {
            isPresented = false
        }
        onDismiss?()
    }
}

// MARK: - Content Height Preference Key

private struct ContentHeightPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - View Modifier

/// Bottom Sheet Modifier
struct GlassBottomSheetModifier<SheetContent: View>: ViewModifier {

    @Binding var isPresented: Bool
    let height: GlassBottomSheetHeight
    let showHandle: Bool
    let title: String?
    let showCloseButton: Bool
    let onDismiss: (() -> Void)?
    let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        content
            .overlay {
                GlassBottomSheet(
                    isPresented: $isPresented,
                    height: height,
                    showHandle: showHandle,
                    title: title,
                    showCloseButton: showCloseButton,
                    onDismiss: onDismiss,
                    content: sheetContent
                )
            }
    }
}

// MARK: - View Extension

extension View {

    /// 添加底部抽屉
    func glassBottomSheet<Content: View>(
        isPresented: Binding<Bool>,
        height: GlassBottomSheetHeight = .fit,
        showHandle: Bool = true,
        title: String? = nil,
        showCloseButton: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(GlassBottomSheetModifier(
            isPresented: isPresented,
            height: height,
            showHandle: showHandle,
            title: title,
            showCloseButton: showCloseButton,
            onDismiss: onDismiss,
            sheetContent: content
        ))
    }
}

// MARK: - Action Sheet Item

/// 操作菜单项
struct GlassActionItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String?
    let style: ActionStyle
    let action: () -> Void

    enum ActionStyle {
        case `default`
        case destructive
        case cancel
    }

    init(_ title: String, icon: String? = nil, style: ActionStyle = .default, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }
}

// MARK: - GlassActionSheet

/// 液态玻璃风格操作菜单
struct GlassActionSheet: View {

    @Binding var isPresented: Bool
    let title: String?
    let message: String?
    let actions: [GlassActionItem]

    var body: some View {
        GlassBottomSheet(
            isPresented: $isPresented,
            height: .fit,
            showHandle: true,
            title: nil,
            showCloseButton: false
        ) {
            VStack(spacing: AppTheme.Spacing.md) {
                // 标题和消息
                if title != nil || message != nil {
                    VStack(spacing: AppTheme.Spacing.xs) {
                        if let title = title {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        if let message = message {
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.bottom, AppTheme.Spacing.sm)
                }

                // 操作按钮
                ForEach(actions) { item in
                    actionButton(for: item)
                }
            }
            .padding(.vertical, AppTheme.Spacing.md)
        }
    }

    @ViewBuilder
    private func actionButton(for item: GlassActionItem) -> some View {
        Button {
            isPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                item.action()
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                if let icon = item.icon {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                }
                Text(item.title)
                    .font(.body)
                Spacer()
            }
            .foregroundStyle(item.style == .destructive ? Color.red : .white)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.md)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Sheet Extension

extension View {

    /// 添加操作菜单
    func glassActionSheet(
        isPresented: Binding<Bool>,
        title: String? = nil,
        message: String? = nil,
        actions: [GlassActionItem]
    ) -> some View {
        self.overlay {
            GlassActionSheet(
                isPresented: isPresented,
                title: title,
                message: message,
                actions: actions
            )
        }
    }
}

// MARK: - Preview

#Preview("Glass Bottom Sheet") {
    struct PreviewWrapper: View {
        @State private var showSheet = false
        @State private var showActionSheet = false
        @State private var showFullSheet = false

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [.gray.opacity(0.2), .gray.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 16) {
                    Button("显示 Bottom Sheet") { showSheet = true }
                    Button("显示 Action Sheet") { showActionSheet = true }
                    Button("显示全屏 Sheet") { showFullSheet = true }
                }
                .buttonStyle(.borderedProminent)
            }
            .glassBottomSheet(isPresented: $showSheet, title: "选择文件夹") {
                VStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { index in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.yellow)
                            Text("文件夹 \(index)")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(AppTheme.CornerRadius.md)
                    }
                }
            }
            .glassActionSheet(
                isPresented: $showActionSheet,
                title: "文件操作",
                message: "选择要执行的操作",
                actions: [
                    GlassActionItem("移动到...", icon: "folder") { print("Move") },
                    GlassActionItem("重命名", icon: "pencil") { print("Rename") },
                    GlassActionItem("分享", icon: "square.and.arrow.up") { print("Share") },
                    GlassActionItem("删除", icon: "trash", style: .destructive) { print("Delete") }
                ]
            )
            .glassBottomSheet(
                isPresented: $showFullSheet,
                height: .fullScreen,
                title: "全屏内容"
            ) {
                VStack(spacing: 12) {
                    ForEach(1...20, id: \.self) { index in
                        HStack {
                            Text("项目 \(index)")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(AppTheme.CornerRadius.md)
                    }
                }
            }
        }
    }

    return PreviewWrapper()
}
