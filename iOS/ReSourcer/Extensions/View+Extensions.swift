//
//  View+Extensions.swift
//  ReSourcer
//
//  View 扩展方法
//

import SwiftUI

// MARK: - Conditional Modifier

extension View {

    /// 条件性应用 modifier
    /// - Parameters:
    ///   - condition: 条件
    ///   - transform: 满足条件时应用的变换
    /// - Returns: 变换后的视图
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// 条件性应用 modifier（带 else 分支）
    @ViewBuilder
    func `if`<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        then trueTransform: (Self) -> TrueContent,
        else falseTransform: (Self) -> FalseContent
    ) -> some View {
        if condition {
            trueTransform(self)
        } else {
            falseTransform(self)
        }
    }

    /// 可选值存在时应用 modifier
    @ViewBuilder
    func ifLet<Value, Content: View>(_ value: Value?, transform: (Self, Value) -> Content) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - Frame Helpers

extension View {

    /// 充满父容器
    func fillParent(alignment: Alignment = .center) -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    /// 充满宽度
    func fillWidth(alignment: Alignment = .center) -> some View {
        self.frame(maxWidth: .infinity, alignment: alignment)
    }

    /// 充满高度
    func fillHeight(alignment: Alignment = .center) -> some View {
        self.frame(maxHeight: .infinity, alignment: alignment)
    }
}

// MARK: - Hide Keyboard

extension View {

    /// 点击时隐藏键盘
    func hideKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

// MARK: - Corner Radius

extension View {

    /// 指定角的圆角
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

/// 自定义圆角形状
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Safe Area

extension View {

    /// 读取安全区域
    func readSafeArea(_ safeArea: Binding<EdgeInsets>) -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        safeArea.wrappedValue = geometry.safeAreaInsets
                    }
                    .onChange(of: geometry.safeAreaInsets) { _, newValue in
                        safeArea.wrappedValue = newValue
                    }
            }
        )
    }
}

// MARK: - Animation Helpers

extension View {

    /// 带弹性动画的过渡
    func bouncyTransition() -> some View {
        self.transition(.scale.combined(with: .opacity))
            .animation(AppTheme.Animation.bouncy, value: UUID())
    }
}

// MARK: - Debug

extension View {

    /// 调试用边框
    func debugBorder(_ color: Color = .red, width: CGFloat = 1) -> some View {
        #if DEBUG
        self.border(color, width: width)
        #else
        self
        #endif
    }

    /// 调试用背景
    func debugBackground(_ color: Color = .red.opacity(0.3)) -> some View {
        #if DEBUG
        self.background(color)
        #else
        self
        #endif
    }
}

// MARK: - Shimmer Effect

/// 闪烁加载效果
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.4),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 400
                }
            }
    }
}

extension View {
    /// 添加闪烁加载效果
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Placeholder

extension View {

    /// 占位符视图
    @ViewBuilder
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// MARK: - Navigation

extension View {

    /// 嵌入导航容器
    func embedInNavigation() -> some View {
        NavigationStack {
            self
        }
    }
}

// MARK: - Preview Helper

extension View {

    /// 预览用包装（添加常用背景）
    func previewWithGlassBackground() -> some View {
        ZStack {
            LinearGradient(
                colors: [.gray.opacity(0.2), .gray.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            self
        }
    }
}
