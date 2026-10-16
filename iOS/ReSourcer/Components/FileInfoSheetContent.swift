//
//  FileInfoSheetContent.swift
//  ReSourcer
//
//  信息面板 = 模块卡片（时间 / 拍摄设备 / 地图定位 / 基础信息）+ 单行操作栏。
//  字段归属严格去重：更丰富的模块拥有字段时，基础信息不重复展示。
//

import MapKit
import SwiftUI

struct FileInfoSheetContent: View {

    let file: FileInfo

    /// 路径元数据（缺省字段不显示）；nil 表示尚未加载或加载失败
    var metadata: FileMetadata? = nil

    /// 画廊序号（如 "3 / 10"），显示在时间模块副标题；不是路径
    var position: String? = nil

    /// 底部额外间距（如 GalleryView 需要给 navbar 留空间）
    var bottomSpacing: CGFloat = 0

    /// 文件标签
    var tags: [Tag] = []

    /// 添加标签回调（nil 则隐藏标签行）
    var onAddTag: (() -> Void)? = nil

    var onRename: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    var onMove: (() -> Void)? = nil
    var onDownload: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onShowDebugLog: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            if showTimeModule {
                timeModule
            }

            if showDeviceModule {
                deviceModule
            }

            if let gps = metadata?.gps {
                mapModule(gps)
            }

            if showBasicsModule {
                basicsModule
            }

            actionsRow

            if bottomSpacing > 0 {
                Spacer().frame(height: bottomSpacing)
            }
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }

    // MARK: - Ownership helpers

    /// 拍摄设备模块：有机身/镜头/EXIF 等“拍摄”信息时显示
    private var showDeviceModule: Bool {
        metadata?.deviceLabel != nil
            || metadata?.lensLine != nil
            || !(metadata?.exifStripItems.isEmpty ?? true)
            || (metadata?.megapixels != nil && hasCaptureContext)
            || (hasCaptureContext && metadata?.format.isEmpty == false)
    }

    /// 有拍摄上下文（设备/镜头/EXIF/拍摄时间）时，dims/size 归拍摄设备
    private var hasCaptureContext: Bool {
        metadata?.deviceLabel != nil
            || metadata?.lensLine != nil
            || !(metadata?.exifStripItems.isEmpty ?? true)
            || (metadata?.captureTime?.isEmpty == false)
    }

    private var showTimeModule: Bool {
        photosDateHeader != nil
    }

    private var showBasicsModule: Bool {
        !basicsRows.isEmpty || onAddTag != nil || file.sourceUrl != nil || onShowDebugLog != nil
    }

    private var photosDateHeader: String? {
        let raw = metadata?.captureTime
        guard let raw, !raw.isEmpty else { return nil }
        return Self.formatPhotosDate(raw)
    }

    /// 拍摄时间已在时间模块展示时，基础信息不再展示同日的创建时间
    private var captureCalendarDay: String? {
        guard let raw = metadata?.captureTime, !raw.isEmpty else { return nil }
        return Self.calendarDayKey(raw)
    }

    // MARK: - 时间

    private var timeModule: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = photosDateHeader {
                Text(header)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .accessibilityIdentifier("meta-capture-time")
            }

            HStack(spacing: 6) {
                Image(systemName: file.isVideo ? "video" : "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(metadata?.filename ?? file.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("meta-filename")
                if let position {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(position)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .moduleCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meta-module-time")
    }

    // MARK: - 拍摄设备

    private var deviceModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let device = metadata?.deviceLabel {
                    Text(device)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("meta-device")
                } else if let lens = metadata?.lensLine {
                    Text(lens)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .accessibilityIdentifier("meta-device")
                } else {
                    Text("拍摄信息")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("meta-device")
                }
                Spacer(minLength: 8)
                if let format = metadata?.format, !format.isEmpty {
                    Text(format)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tertiary.opacity(0.35), in: Capsule())
                        .accessibilityIdentifier("meta-format")
                }
            }

            if metadata?.deviceLabel != nil, let lens = metadata?.lensLine {
                Text(lens)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("meta-lens")
            }

            if let summary = deviceResolutionSummary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("meta-dimensions")
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
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.top, 2)
                .accessibilityIdentifier("meta-exif-strip")
            }
        }
        .moduleCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meta-module-device")
    }

    /// MP • dims • size — owned by 拍摄设备 when that module shows
    private var deviceResolutionSummary: String? {
        var parts: [String] = []
        if let megapixels = metadata?.megapixels {
            let mp = megapixels >= 10
                ? String(format: "%.0f MP", megapixels)
                : String(format: "%.1f MP", megapixels)
            parts.append(mp)
        }
        if let dims = metadata?.formattedDimensions {
            parts.append(dims)
        } else if let w = file.width, let h = file.height {
            parts.append("\(w) × \(h)")
        }
        parts.append(metadata?.formattedSize ?? file.formattedSize)
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    // MARK: - 地图定位

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
                    .accessibilityIdentifier("meta-gps-coords")
            }
        }
        .moduleCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meta-module-gps")
    }

    // MARK: - 基础信息（仅剩余字段）

    private struct BasicsRow: Identifiable {
        let id: String
        let label: String
        let value: String
    }

    private var basicsRows: [BasicsRow] {
        var rows: [BasicsRow] = []

        // Filename lives in 时间 subtitle when that module shows; otherwise 基础信息
        if !showTimeModule {
            rows.append(BasicsRow(id: "filename", label: "文件名", value: metadata?.filename ?? file.name))
        }

        // Path / folder location (not gallery index)
        let folder = (file.path as NSString).deletingLastPathComponent
        if !folder.isEmpty, folder != "." {
            rows.append(BasicsRow(id: "path", label: "路径", value: folder))
        }

        // Format / dims / size only when 拍摄设备 is hidden
        if !showDeviceModule {
            if let format = metadata?.format, !format.isEmpty {
                rows.append(BasicsRow(id: "format", label: "格式", value: format))
            } else {
                let ext = file.extensionLabel
                if !ext.isEmpty {
                    rows.append(BasicsRow(id: "format", label: "格式", value: ext))
                }
            }
            if let dims = metadata?.formattedDimensions {
                rows.append(BasicsRow(id: "dims", label: "分辨率", value: dims))
            } else if let w = file.width, let h = file.height {
                rows.append(BasicsRow(id: "dims", label: "分辨率", value: "\(w) × \(h)"))
            }
            rows.append(BasicsRow(
                id: "size",
                label: "大小",
                value: metadata?.formattedSize ?? file.formattedSize
            ))
        }

        // Codec / duration → 基础信息
        if let duration = metadata?.formattedDuration ?? file.formattedDuration {
            rows.append(BasicsRow(id: "duration", label: "时长", value: duration))
        }
        if let codec = metadata?.codec, !codec.isEmpty {
            rows.append(BasicsRow(id: "codec", label: "编码", value: codec.uppercased()))
        }

        // Created / modified — omit if same calendar day as capture time already in 时间
        let createdRaw = metadata?.created ?? file.created
        let modifiedRaw = metadata?.modified ?? file.modified
        if shouldShowFilesystemTime(createdRaw) {
            rows.append(BasicsRow(
                id: "created",
                label: "创建时间",
                value: createdRaw.toLocalDateTime
            ))
        }
        if shouldShowFilesystemTime(modifiedRaw),
           Self.normalizeTime(modifiedRaw) != Self.normalizeTime(createdRaw) {
            rows.append(BasicsRow(
                id: "modified",
                label: "修改时间",
                value: modifiedRaw.toLocalDateTime
            ))
        }

        return rows
    }

    private func shouldShowFilesystemTime(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // If capture time module is showing and this FS time is the same calendar day, skip
        if showTimeModule, let captureDay = captureCalendarDay,
           let day = Self.calendarDayKey(trimmed), day == captureDay {
            return false
        }
        return true
    }

    private var basicsModule: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基础信息")
                .font(.subheadline.weight(.semibold))

            ForEach(basicsRows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("meta-basics-\(row.id)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

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
            }

            if let sourceUrl = file.sourceUrl, let url = URL(string: sourceUrl) {
                VStack(alignment: .leading, spacing: 2) {
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
                }
                .buttonStyle(.plain)
            }
        }
        .moduleCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meta-module-basics")
    }

    // MARK: - Actions (single row)

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
            .padding(.top, AppTheme.Spacing.xs)
        }
    }

    // MARK: - Date helpers

    private static func formatPhotosDate(_ raw: String) -> String? {
        guard let date = parseDate(raw) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.dateFormat = "EEEE • M月d日 • HH:mm"
        return out.string(from: date)
    }

    private static func calendarDayKey(_ raw: String) -> String? {
        guard let date = parseDate(raw) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func normalizeTime(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(19))
    }

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let a = DateFormatter()
        a.locale = Locale(identifier: "en_US_POSIX")
        a.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let b = DateFormatter()
        b.locale = Locale(identifier: "en_US_POSIX")
        b.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let head = String(trimmed.prefix(19))
        return a.date(from: head) ?? b.date(from: head) ?? ISO8601DateFormatter().date(from: trimmed)
    }
}

// MARK: - Module card chrome (native Liquid Glass)

private extension View {
    func moduleCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
