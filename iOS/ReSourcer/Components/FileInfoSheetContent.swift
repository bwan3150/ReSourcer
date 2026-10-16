//
//  FileInfoSheetContent.swift
//  ReSourcer
//
//  Apple Photos–style file info panel. Actions live inside this panel.
//

import MapKit
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
    var onMove: (() -> Void)? = nil
    var onDownload: (() -> Void)? = nil
    /// 删除回调（软删除到回收站，nil 则隐藏；回收站内应隐藏）
    var onDelete: (() -> Void)? = nil

    /// 调试日志按钮（nil 则隐藏）
    var onShowDebugLog: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            headerCard

            if hasCameraSection {
                cameraCard
            }

            if let gps = metadata?.gps {
                gpsCard(gps)
            }

            if let onAddTag {
                tagsRow(onAddTag: onAddTag)
            }

            if let sourceUrl = file.sourceUrl, let url = URL(string: sourceUrl) {
                sourceLink(url: url, text: sourceUrl)
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
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
            }

            actionsSection

            if bottomSpacing > 0 {
                Spacer().frame(height: bottomSpacing)
            }
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }

    // MARK: - Header (date • filename)

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(photosDateHeader)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Image(systemName: file.isVideo ? "video" : "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(metadata?.filename ?? file.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let position {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(position)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - Camera / EXIF

    private var hasCameraSection: Bool {
        metadata?.deviceLabel != nil
            || metadata?.lensLine != nil
            || metadata?.resolutionSummary != nil
            || !(metadata?.exifStripItems.isEmpty ?? true)
            || metadata?.format.isEmpty == false
            || metadata?.codec != nil
            || metadata?.formattedDuration != nil
    }

    private var cameraCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let device = metadata?.deviceLabel {
                    Text(device)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 8)
                if let format = metadata?.format, !format.isEmpty {
                    Text(format)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            if let lens = metadata?.lensLine {
                Text(lens)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let summary = metadata?.resolutionSummary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let duration = metadata?.formattedDuration ?? file.formattedDuration {
                Text("时长 \(duration)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let codec = metadata?.codec, !codec.isEmpty {
                Text(codec.uppercased())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            let strip = metadata?.exifStripItems ?? []
            if !strip.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(strip.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.35))
                                .frame(width: 1, height: 18)
                                .padding(.horizontal, 8)
                        }
                        Text(item.value)
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - GPS

    private func gpsCard(_ gps: FileGpsCoords) -> some View {
        let coord = CLLocationCoordinate2D(latitude: gps.lat, longitude: gps.lon)
        return VStack(alignment: .leading, spacing: 8) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                Marker("", coordinate: coord)
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .allowsHitTesting(false)

            Text(gps.formatted)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - Tags / source / actions

    private func tagsRow(onAddTag: @escaping () -> Void) -> some View {
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
                    Button(action: onAddTag) {
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
        .padding(14)
        .background(cardBackground)
    }

    private func sourceLink(url: URL, text: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            Text("来源地址")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(destination: url) {
                HStack(spacing: 4) {
                    Text(text)
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
        .padding(14)
        .background(cardBackground)
    }

    @ViewBuilder
    private var actionsSection: some View {
        let hasActions = onRename != nil || onMove != nil || onDownload != nil || onDelete != nil
        if hasActions {
            VStack(spacing: AppTheme.Spacing.sm) {
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
                if let onDelete {
                    GlassButton("删除", icon: "trash", style: .destructive, size: .medium, action: onDelete)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, AppTheme.Spacing.sm)
        }
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
    }

    private var photosDateHeader: String {
        let raw = metadata?.captureTime ?? metadata?.created ?? file.created
        if let formatted = Self.formatPhotosDate(raw), !formatted.isEmpty {
            return formatted
        }
        return metadata?.filename ?? file.name
    }

    private static func formatPhotosDate(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let a = DateFormatter()
        a.locale = Locale(identifier: "en_US_POSIX")
        a.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let b = DateFormatter()
        b.locale = Locale(identifier: "en_US_POSIX")
        b.dateFormat = "yyyy:MM:dd HH:mm:ss"

        var date: Date?
        let head = String(trimmed.prefix(19))
        date = a.date(from: head) ?? b.date(from: head)
        if date == nil {
            date = ISO8601DateFormatter().date(from: trimmed)
        }
        guard let date else { return trimmed }

        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.dateFormat = "EEEE • M月d日 • HH:mm"
        return out.string(from: date)
    }
}
