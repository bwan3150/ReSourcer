//
//  SeekDragGesture.swift
//  ReSourcer
//
//  未放大时，视频画面任意位置左右拖动 → 按拖动距离换算时间偏移（相对当前播放位置），
//  拖动中显示 HUD，松手才真正 seek。
//

import SwiftUI

struct SeekDragGesture: ViewModifier {

    /// 仅在未放大（scale == 1.0）时启用，放大态必须保留原有平移行为
    let isEnabled: Bool
    let currentTime: Double
    let duration: Double
    /// 松手后调用，携带最终目标时间（秒）
    let onSeek: (Double) -> Void

    @State private var dragStartTime: Double?
    @State private var previewOffset: Double = 0

    /// 每点像素对应的秒数
    private let sensitivity: Double = 0.4

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(isEnabled ? dragGesture : nil)
            .overlay(alignment: .top) {
                if let start = dragStartTime {
                    SeekHUDView(targetTime: clampedTarget(from: start), offset: previewOffset)
                        .padding(.top, 64)
                        .transition(.opacity)
                }
            }
    }

    private func clampedTarget(from start: Double) -> Double {
        min(max(start + previewOffset, 0), max(duration, 0))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if dragStartTime == nil {
                    dragStartTime = currentTime
                }
                previewOffset = Double(value.translation.width) * sensitivity
            }
            .onEnded { value in
                guard let start = dragStartTime else { return }
                let isHorizontalDrag = abs(value.translation.width) > abs(value.translation.height)
                let target = clampedTarget(from: start)
                dragStartTime = nil
                previewOffset = 0
                if isHorizontalDrag {
                    onSeek(target)
                }
            }
    }
}

extension View {
    /// scale == 1.0 时，水平拖动 seek 视频，拖动中显示目标时间 HUD。
    func seekDragGesture(
        isEnabled: Bool,
        currentTime: Double,
        duration: Double,
        onSeek: @escaping (Double) -> Void
    ) -> some View {
        modifier(SeekDragGesture(isEnabled: isEnabled, currentTime: currentTime, duration: duration, onSeek: onSeek))
    }
}

/// Seek 拖动过程中显示的 HUD：目标时间 + 相对偏移量
private struct SeekHUDView: View {
    let targetTime: Double
    let offset: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: offset >= 0 ? "goforward" : "gobackward")
            Text(formatTime(targetTime))
                .monospacedDigit()
            Text(offset >= 0 ? "+\(formatOffset(offset))" : "-\(formatOffset(-offset))")
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6), in: Capsule())
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formatOffset(_ seconds: Double) -> String {
        String(format: "%.0fs", abs(seconds))
    }
}
