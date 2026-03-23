//
//  FileInfoSheetContent.swift
//  ReSourcer
//
//  共享的文件信息面板内容（用于 glassBottomSheet）
//

import SwiftUI

struct FileInfoSheetContent: View {

    let file: FileInfo

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
    var onMove: (() -> Void)? = nil
    var onDownload: (() -> Void)? = nil

    /// 调试日志按钮（nil 则隐藏）
    var onShowDebugLog: (() -> Void)? = nil

    /// 创建/修改时间切换状态
    @State private var showCreatedTime = true

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            infoRow("文件名", value: file.name)

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
                            // ⊕ 添加按钮
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
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let position {
                infoRow("位置", value: position)
            }

            infoRow("大小", value: file.formattedSize)

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
                    Text(showCreatedTime ? file.created.toLocalDateTime : file.modified.toLocalDateTime)
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

            if let width = file.width, let height = file.height {
                infoRow("分辨率", value: "\(width) × \(height)")
            }
            if let duration = file.formattedDuration {
                infoRow("时长", value: duration)
            }

            // 调试日志入口（信息行末尾）
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

            // 操作按钮
            let hasActions = onRename != nil || onMove != nil || onDownload != nil
            if hasActions {
                HStack(spacing: AppTheme.Spacing.md) {
                    if let onRename {
                        GlassButton("重命名", icon: "pencil", style: .secondary, size: .medium, action: onRename)
                            .frame(maxWidth: .infinity)
                    }
                    if let onMove {
                        GlassButton("移动", icon: "folder", style: .secondary, size: .medium, action: onMove)
                            .frame(maxWidth: .infinity)
                    }
                    if let onDownload {
                        GlassButton("下载", icon: "arrow.down.circle", style: .secondary, size: .medium, action: onDownload)
                            .frame(maxWidth: .infinity)
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
