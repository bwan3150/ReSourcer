//
//  FileInfoSheetContent.swift
//  ReSourcer
//
//  共享的文件信息面板内容（用于 glassBottomSheet）
//  保留原 label/value 行设计，并在其后扩展相机/编解码等元数据字段。
//

import SwiftUI

struct FileInfoSheetContent: View {

    let file: FileInfo

    /// 路径元数据（缺省字段不显示）；nil 表示尚未加载或加载失败
    var metadata: FileMetadata? = nil

    /// 文件位置信息（如 "3 / 10"），nil 则不显示
    var position: String? = nil

    /// 底部额外间距（如 GalleryView 需要给 navbar 留空间）
    var bottomSpacing: CGFloat = 0

    /// 文件标签
    var tags: [Tag] = []

    /// 添加标签回调（nil 则隐藏标签行）
    var onAddTag: (() -> Void)? = nil

    /// 操作按钮闭包（nil 则隐藏该按钮）
    var onRename: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    var onMove: (() -> Void)? = nil
    var onDownload: (() -> Void)? = nil
    /// 删除回调（软删除到回收站，nil 则隐藏；回收站内应隐藏）
    var onDelete: (() -> Void)? = nil

    /// 调试日志按钮（nil 则隐藏）
    var onShowDebugLog: (() -> Void)? = nil

    /// 创建/修改时间切换状态
    @State private var showCreatedTime = true

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            infoRow("文件名", value: metadata?.filename ?? file.name)

            if let format = metadata?.format, !format.isEmpty {
                infoRow("格式", value: format)
            }

            // 标签行：紧跟文件名下方
            if let onAddTag {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text("标签")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tags) { tag in
                                Text(tag.name)
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(hex: tag.color).opacity(0.85))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                            Button {
                                onAddTag()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .overlay(Capsule().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("添加标签")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let position {
                infoRow("位置", value: position)
            }

            infoRow("大小", value: metadata?.formattedSize ?? file.formattedSize)

            if let dims = metadata?.formattedDimensions {
                infoRow("分辨率", value: dims)
            } else if let width = file.width, let height = file.height {
                infoRow("分辨率", value: "\(width) × \(height)")
            }

            if let capture = metadata?.captureTime, !capture.isEmpty {
                infoRow("拍摄时间", value: capture)
            }

            if let gps = metadata?.gps {
                infoRow("GPS", value: gps.formatted)
            }

            if let duration = metadata?.formattedDuration ?? file.formattedDuration {
                infoRow("时长", value: duration)
            }

            // 扩展元数据（缺省则隐藏）— 追加在原字段之后
            if let device = metadata?.deviceLabel {
                infoRow("设备", value: device)
            }
            if let lens = metadata?.lens, !lens.isEmpty {
                infoRow("镜头", value: lens)
            }
            if let megapixels = metadata?.megapixels {
                let mp = megapixels >= 10
                    ? String(format: "%.0f MP", megapixels)
                    : String(format: "%.1f MP", megapixels)
                infoRow("像素", value: mp)
            }
            if let fl = metadata?.focalLength35mm ?? metadata?.focalLengthMm.map({ UInt32($0.rounded()) }) {
                infoRow("焦距", value: "\(fl) mm")
            }
            if let aperture = metadata?.aperture {
                infoRow("光圈", value: String(format: "ƒ%.2g", aperture))
            }
            if let iso = metadata?.iso {
                infoRow("ISO", value: "\(iso)")
            }
            if let shutter = metadata?.shutterSpeed, !shutter.isEmpty {
                infoRow("快门", value: shutter)
            }
            if let ev = metadata?.exposureCompensation {
                let label = abs(ev) < 0.05 ? "0 EV" : String(format: "%+.1f EV", ev)
                infoRow("曝光补偿", value: label)
            }
            if let codec = metadata?.codec, !codec.isEmpty {
                infoRow("编码", value: codec.uppercased())
            }

            // 创建/修改时间合并为一行，点击切换
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showCreatedTime.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    HStack(spacing: 4) {
                        Text(showCreatedTime ? "创建时间" : "修改时间")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Text(showCreatedTime
                         ? (metadata?.created ?? file.created).toLocalDateTime
                         : (metadata?.modified ?? file.modified).toLocalDateTime)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let sourceUrl = file.sourceUrl, let url = URL(string: sourceUrl) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text("来源地址")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text(sourceUrl)
                                .font(.body)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let onShowDebugLog {
                Button(action: onShowDebugLog) {
                    HStack {
                        Text("调试日志")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            // 操作：下载 / 分享 / 移动 / 重命名 / 删除 — 单行，原生 GlassButton
            let hasActions = onDownload != nil || onShare != nil || onMove != nil
                || onRename != nil || onDelete != nil
            if hasActions {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if let onDownload {
                        GlassButton(icon: "arrow.down.circle", style: .secondary, size: .medium, action: onDownload)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("下载")
                    }
                    if let onShare {
                        GlassButton(icon: "square.and.arrow.up", style: .secondary, size: .medium, action: onShare)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("分享")
                    }
                    if let onMove {
                        GlassButton(icon: "folder", style: .secondary, size: .medium, action: onMove)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("移动")
                    }
                    if let onRename {
                        GlassButton(icon: "pencil", style: .secondary, size: .medium, action: onRename)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("重命名")
                    }
                    if let onDelete {
                        GlassButton(icon: "trash", style: .destructive, size: .medium, action: onDelete)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("删除")
                    }
                }
                .padding(.top, AppTheme.Spacing.sm)
            }

            if bottomSpacing > 0 {
                Spacer().frame(height: bottomSpacing)
            }
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }

    // MARK: - Info Row

    private func infoRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
