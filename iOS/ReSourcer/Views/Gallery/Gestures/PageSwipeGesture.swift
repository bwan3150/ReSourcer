//
//  PageSwipeGesture.swift
//  ReSourcer
//
//  未放大时，图片区域左右滑动切换上一张/下一张。
//

import SwiftUI

struct PageSwipeGesture: ViewModifier {

    /// 仅在未放大（scale == 1.0）时启用，放大态必须保留原有平移行为
    let isEnabled: Bool
    /// direction: -1 = 上一张，+1 = 下一张。返回 false 表示已到头（没有可切换的目标）
    let onSwipe: (Int) -> Bool

    @State private var dragOffset: CGFloat = 0

    private let threshold: CGFloat = 80

    func body(content: Content) -> some View {
        content
            .offset(x: dragOffset)
            .simultaneousGesture(isEnabled ? dragGesture : nil)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = value.translation.width * 0.4
            }
            .onEnded { value in
                let dx = value.translation.width
                let isHorizontalSwipe = abs(dx) > abs(value.translation.height) && abs(dx) > threshold
                let direction = dx < 0 ? 1 : -1

                let reachedBoundary = isHorizontalSwipe && !onSwipe(direction)
                if reachedBoundary {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    dragOffset = 0
                }
            }
    }
}

extension View {
    /// scale == 1.0 时，水平滑动超过阈值触发翻页；到头时给出边界反馈而不是静默无响应。
    func pageSwipeGesture(isEnabled: Bool, onSwipe: @escaping (Int) -> Bool) -> some View {
        modifier(PageSwipeGesture(isEnabled: isEnabled, onSwipe: onSwipe))
    }
}
