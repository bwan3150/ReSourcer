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

    /// 操作按钮闭包（nil 则隐藏该按钮）
    var onRename: (() -> Void)? = nil
    var onMove: (() -> Void)? = nil
    var onDownload: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            infoRow("文件名", value: file.name)

            if let position {
                infoRow("位置", value: position)
            }

            infoRow("类型", value: file.extension.uppercased())
            infoRow("大小", value: file.formattedSize)
            infoRow("创建时间", value: file.created)
            infoRow("修改时间", value: file.modified)

            if let width = file.width, let height = file.height {
                infoRow("分辨率", value: "\(width) × \(height)")
            }
            if let duration = file.formattedDuration {
                infoRow("时长", value: duration)
            }

            // 操作按钮（只显示传入了闭包的按钮）
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
