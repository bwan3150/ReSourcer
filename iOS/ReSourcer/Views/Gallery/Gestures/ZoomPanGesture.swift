//
//  ZoomPanGesture.swift
//  ReSourcer
//
//  双指缩放 + 放大后拖动平移 + 双击重置缩放。
//  从 FilePreviewView 的图片/视频预览中抽出，两者共用同一份缩放/平移逻辑。
//

import SwiftUI

struct ZoomPanGesture: ViewModifier {

    @Binding var scale: CGFloat

    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero

    /// 实时偏移 = 上次结束位置 + 当前拖拽距离
    private var offset: CGSize {
        CGSize(
            width: lastOffset.width + dragTranslation.width,
            height: lastOffset.height + dragTranslation.height
        )
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .gesture(pinchGesture)
            .simultaneousGesture(scale > 1.0 ? panGesture : nil)
            .onTapGesture(count: 2) { resetZoom() }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 0.5), 4.0)
            }
            .onEnded { _ in
                lastScale = scale
                if scale < 1.0 {
                    withAnimation(AppTheme.Animation.spring) {
                        scale = 1.0
                        lastScale = 1.0
                        lastOffset = .zero
                    }
                }
            }
    }

    /// 平移手势（仅放大时启用，由调用方通过 scale 控制是否接入）
    private var panGesture: some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                lastOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
    }

    private func resetZoom() {
        withAnimation(AppTheme.Animation.spring) {
            scale = scale > 1.0 ? 1.0 : 2.0
            lastScale = scale
            lastOffset = .zero
        }
    }
}

extension View {
    /// 接入双指缩放 + 放大后拖动平移 + 双击重置缩放。
    /// `scale` 以 Binding 回传，供调用方判断当前是否处于放大态（决定要不要接入其他水平手势）。
    func zoomPanGesture(scale: Binding<CGFloat>) -> some View {
        modifier(ZoomPanGesture(scale: scale))
    }
}
