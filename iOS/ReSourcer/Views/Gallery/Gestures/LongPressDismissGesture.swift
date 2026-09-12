//
//  LongPressDismissGesture.swift
//  ReSourcer
//
//  在媒体显示区域长按 → 退出预览，回到 Gallery 列表。
//  单手持机时够不到左上角关闭按钮，长按画面是更好触达的替代路径（不是替代按钮，是补充）。
//

import SwiftUI

struct LongPressDismissGesture: ViewModifier {

    /// 触发退出所需的最短按住时长
    let minimumDuration: Double
    /// 按住期间允许的最大位移；超过则视为在平移/缩放/seek，取消退出
    let maximumDistance: CGFloat
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                LongPressGesture(minimumDuration: minimumDuration, maximumDistance: maximumDistance)
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onDismiss()
                    }
            )
    }
}

extension View {
    /// 媒体区域长按退出预览。`maximumDistance` 内建的位移容差与手指移动即取消的语义，
    /// 天然和平移/缩放/seek 等其他拖动手势互不打架 —— 一旦移动超出容差，长按识别直接失败。
    func longPressToDismiss(
        minimumDuration: Double = 0.55,
        maximumDistance: CGFloat = 14,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(LongPressDismissGesture(
            minimumDuration: minimumDuration,
            maximumDistance: maximumDistance,
            onDismiss: onDismiss
        ))
    }
}
