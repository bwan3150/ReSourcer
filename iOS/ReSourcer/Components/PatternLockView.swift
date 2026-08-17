//
//  PatternLockView.swift
//  ReSourcer
//
//  9 宫格手势图案锁 - 支持「校验」与「设置新图案」两种用途
//  设置时需连续绘制两次一致方可保存；校验时与 Keychain 中的哈希比对
//

import SwiftUI

struct PatternLockView: View {

    /// 用途
    enum Purpose {
        case verify   // 校验已有图案（用于解锁私密）
        case setNew   // 设置新图案（首次为私密设置手势）
    }

    let purpose: Purpose
    /// 取消回调
    let onCancel: () -> Void
    /// 成功回调（verify 校验通过 / setNew 设置完成）
    let onSuccess: () -> Void

    /// 至少需要连接的点数
    private let minDots = 4
    private let gridSize: CGFloat = 260

    @State private var selected: [Int] = []       // 当前绘制的点序列
    @State private var dragLocation: CGPoint? = nil
    @State private var firstPass: [Int]? = nil     // setNew 第一次绘制记录
    @State private var message = ""
    @State private var isError = false
    @State private var shakePhase: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: AppTheme.Spacing.lg) {
                Text(titleText)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(message.isEmpty ? " " : message)
                    .font(.subheadline)
                    .foregroundStyle(isError ? .red : .secondary)

                grid
                    .frame(width: gridSize, height: gridSize)
                    .modifier(ShakeEffect(phase: shakePhase))

                GlassButton("取消", style: .secondary, size: .medium) {
                    onCancel()
                }
                .frame(maxWidth: 160)
            }
            .padding(AppTheme.Spacing.xxl)
            .frame(maxWidth: 340)
            .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.xl))
            .padding(.horizontal, AppTheme.Spacing.xl)
        }
    }

    // MARK: - 标题

    private var titleText: String {
        switch purpose {
        case .verify:
            return "绘制手势以解锁私密"
        case .setNew:
            return firstPass == nil ? "绘制新手势图案" : "再次绘制以确认"
        }
    }

    // MARK: - 九宫格

    private var grid: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // 已连线 + 到手指的临时连线
                Path { path in
                    guard let first = selected.first else { return }
                    path.move(to: dotCenter(first, in: size))
                    for idx in selected.dropFirst() {
                        path.addLine(to: dotCenter(idx, in: size))
                    }
                    if let drag = dragLocation, let last = selected.last {
                        path.move(to: dotCenter(last, in: size))
                        path.addLine(to: drag)
                    }
                }
                .stroke(isError ? Color.red : Color.blue,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                // 9 个圆点
                ForEach(0..<9, id: \.self) { idx in
                    let active = selected.contains(idx)
                    Circle()
                        .fill(active ? (isError ? Color.red : Color.blue) : Color.gray.opacity(0.25))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1.5)
                        )
                        .position(dotCenter(idx, in: size))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if isError { clearCurrent() }
                        dragLocation = value.location
                        let threshold = size.width / 3 * 0.34
                        for idx in 0..<9 where !selected.contains(idx) {
                            let c = dotCenter(idx, in: size)
                            if hypot(value.location.x - c.x, value.location.y - c.y) < threshold {
                                selected.append(idx)
                            }
                        }
                    }
                    .onEnded { _ in
                        dragLocation = nil
                        finish()
                    }
            )
        }
    }

    /// 计算某个点的中心坐标（index = row*3 + col）
    private func dotCenter(_ index: Int, in size: CGSize) -> CGPoint {
        let cell = size.width / 3
        let col = CGFloat(index % 3)
        let row = CGFloat(index / 3)
        return CGPoint(x: (col + 0.5) * cell, y: (row + 0.5) * cell)
    }

    // MARK: - 状态处理

    private func clearCurrent() {
        selected = []
        isError = false
        if purpose == .setNew && firstPass != nil {
            message = "再次绘制以确认"
        } else {
            message = ""
        }
    }

    private func finish() {
        // 点数不足：提示并重置
        guard selected.count >= minDots else {
            if !selected.isEmpty {
                message = "至少连接 \(minDots) 个点"
                isError = true
                triggerShake()
            }
            selected = []
            return
        }

        switch purpose {
        case .verify:
            if PrivacyManager.shared.verifyPattern(selected) {
                onSuccess()
            } else {
                message = "手势错误，请重试"
                isError = true
                triggerShake()
            }

        case .setNew:
            if let first = firstPass {
                if first == selected {
                    PrivacyManager.shared.setPattern(selected)
                    onSuccess()
                } else {
                    message = "两次手势不一致，请重新设置"
                    isError = true
                    firstPass = nil
                    triggerShake()
                }
            } else {
                firstPass = selected
                selected = []
                message = "再次绘制以确认"
            }
        }
    }

    private func triggerShake() {
        withAnimation(.linear(duration: 0.4)) {
            shakePhase += 1
        }
    }
}

// MARK: - 抖动动画

/// 水平抖动动效（用于错误提示）
struct ShakeEffect: GeometryEffect {
    var phase: CGFloat
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = 10 * sin(phase * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}
