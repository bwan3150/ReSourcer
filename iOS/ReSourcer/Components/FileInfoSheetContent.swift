//
//  FileInfoSheetContent.swift
//  ReSourcer
//
//  文件信息面板：Apple Photos 风格模块（时间 / 设备 / 地图）+ 原有 label/value 行。
//  缺数据时整块模块隐藏；操作为单行 GlassButton（含分享）。
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
            // ── Photos-style modules (hide when empty) ──
            if let header = photosDateHeader {
                timeModule(header: header)
            }

            if showDeviceModule {
                deviceModule
            }

            if let gps = metadata?.gps {
                mapModule(gps)
            }

            // ── Original label/value detail fields ──
            infoRow("文件名", value: metadata?.filename ?? file.name)

            if let format = metadata?.format, !format.isEmpty {
                infoRow("格式", value: format)
            }

            if let onAddTag {
                tagsRow(onAddTag: onAddTag)
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

            actionsRow

            if bottomSpacing > 0 {
                Spacer().frame(height: bottomSpacing)
            }
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }

    // MARK: - Time module

    private func timeModule(header: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Image(systemName: file.isVideo ? "video" : "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
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
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Device module

    private var showDeviceModule: Bool {
        metadata?.deviceLabel != nil
            || metadata?.lensLine != nil
            || metadata?.resolutionSummary != nil
            || !(metadata?.exifStripItems.isEmpty ?? true)
            || (metadata?.format.isEmpty == false)
            || metadata?.codec != nil
            || (metadata?.formattedDuration ?? file.formattedDuration) != nil
    }

    private var deviceModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let device = metadata?.deviceLabel {
                    Text(device)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                } else {
                    Text(metadata?.format ?? file.extensionLabel)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 8)
                if let format = metadata?.format, !format.isEmpty {
                    Text(format)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tertiary.opacity(0.35), in: Capsule())
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
                                .padding(.horizontal, 6)
                        }
                        Text(item.value)
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Map module

    private func mapModule(_ gps: FileGpsCoords) -> some View {
        let coord = CLLocationCoordinate2D(latitude: gps.lat, longitude: gps.lon)
        return VStack(alignment: .leading, spacing: 8) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            ))) {
                Marker("", coordinate: coord)
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .allowsHitTesting(false)

            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(gps.formatted)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Tags / actions

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
                    .accessibilityLabel("添加标签")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionsRow: some View {
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
    }

    // MARK: - Helpers

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

    /// Photos-style `星期 • 日期 • 时间`, or nil when no parseable capture/created time.
    private var photosDateHeader: String? {
        let raw = metadata?.captureTime ?? metadata?.created ?? file.created
        return Self.formatPhotosDate(raw)
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

        let head = String(trimmed.prefix(19))
        var date = a.date(from: head) ?? b.date(from: head)
        if date == nil {
            date = ISO8601DateFormatter().date(from: trimmed)
        }
        guard let date else { return nil }

        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.dateFormat = "EEEE • M月d日 • HH:mm"
        return out.string(from: date)
    }
}
