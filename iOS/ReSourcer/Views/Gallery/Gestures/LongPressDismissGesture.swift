//
//  LongPressDismissGesture.swift
//  ReSourcer
//
//  在媒体显示区域长按 → 退出预览，回到 Gallery 列表。
//  单手持机时够不到左上角关闭按钮，长按画面是更好触达的替代路径（不是替代按钮，是补充）。
//

import SwiftUI

struct LongPressDismissGesture: ViewModifier {

    /// 触发退出所需的最短按住时长（必须是这段时间内完全没有新位移，见下）
    let minimumDuration: Double
    /// 按住期间允许的最大位移；从按下起累计位移一旦超过，本次按住永久作废
    let maximumDistance: CGFloat
    let onDismiss: () -> Void

    @State private var armedWorkItem: DispatchWorkItem?
    @State private var exceededTolerance = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                // 用 .global 坐标系自己量位移：媒体区域内部的 ZoomPanGesture/PageSwipeGesture
                // 会对内容做 .offset()，若在局部坐标系里量距离，位移会被内容跟手位移抵消，
                // 导致慢速平移也测不出超出容差（曾在真机上复现：慢速拖动被误判为长按未移动）。
                //
                // 计时器不能挂在「按下」那一刻算固定截止时间——慢速拖动在到点那一刻的
                // 位移可能还没超容差，稍后才越过，可提前排定的 dismiss 早已执行完。
                // 改成每次 onChanged 都重新排定计时器（防抖）：只要手指还在动就不断把
                // 截止时间往后推，真正静止 minimumDuration 才会触发；一旦累计位移超容差，
                // 整次按住永久作废，不再重新武装。
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        guard !exceededTolerance else { return }

                        let distance = hypot(value.translation.width, value.translation.height)
                        armedWorkItem?.cancel()
                        if distance > maximumDistance {
                            exceededTolerance = true
                            armedWorkItem = nil
                            return
                        }

                        let workItem = DispatchWorkItem { [onDismiss] in
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onDismiss()
                        }
                        armedWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + minimumDuration, execute: workItem)
                    }
                    .onEnded { _ in
                        exceededTolerance = false
                        armedWorkItem?.cancel()
                        armedWorkItem = nil
                    }
            )
    }
}

extension View {
    /// 媒体区域长按退出预览。位移在 `.global` 坐标系里测量，不受内容自身的
    /// 平移/缩放 `.offset()` 影响；只要手指还在移动就不断重新起算静止时长，
    /// 累计位移一旦超出 `maximumDistance` 便永久取消本次长按，
    /// 天然和平移/缩放/seek 等其他拖动手势互不打架。
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
