//
//  ServerMetricsView.swift
//  ReSourcer
//
//  Server performance monitoring dashboard
//

import SwiftUI

struct ServerMetricsView: View {

    let apiService: APIService

    @State private var current: MetricsSnapshot?
    @State private var systemInfo: MetricsSystemInfo?
    @State private var snapshots: [MetricsSnapshot] = []
    @State private var disks: [MetricsDiskInfo] = []
    @State private var rangeMinutes = 60
    @State private var isLoading = true

    private let pollInterval: TimeInterval = 5
    private let historyInterval: TimeInterval = 30
    private let rangeOptions = [(5, "5m"), (30, "30m"), (60, "1h"), (360, "6h"), (1440, "24h")]

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                // System info + Uptime
                systemAndUptimeSection

                // Live stats
                liveStatsSection

                // History charts
                historySection

                // Disk details
                diskSection
            }
            .padding(AppTheme.Spacing.lg)
        }
        .navigationTitle("服务器性能")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAll()
            isLoading = false
        }
        .task(id: "poll") {
            // Poll current every 5s
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                await loadCurrent()
            }
        }
        .task(id: "history") {
            // Refresh history every 30s
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(historyInterval * 1_000_000_000))
                await loadHistory()
            }
        }
    }

    // MARK: - System & Uptime

    private var systemAndUptimeSection: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // System
            VStack(spacing: 4) {
                Text("系统")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let info = systemInfo {
                    Text("\(info.osName) \(info.arch)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .fontDesign(.monospaced)

                    Text("\(info.hostname) · \(info.cpuCount) cores")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    ProgressView()
                        .frame(height: 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.md)
            .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))

            // Uptime
            VStack(spacing: 4) {
                Text("运行时间")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let c = current {
                    Text(formatUptime(c.uptimeSeconds))
                        .font(.title3)
                        .fontWeight(.bold)
                        .fontDesign(.monospaced)

                    if let sysUp = c.systemUptimeSeconds, sysUp > 0 {
                        Text("系统: \(formatUptime(sysUp))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    ProgressView()
                        .frame(height: 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.md)
            .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
        }
    }

    // MARK: - Live Stats

    private var liveStatsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.md) {
            // CPU
            statCard(
                label: "CPU",
                value: current.map { String(format: "%.1f%%", $0.cpuUsagePercent) },
                percent: current?.cpuUsagePercent,
                detail: current.map { "Load \(String(format: "%.2f", $0.loadAvg1M)) · \(String(format: "%.2f", $0.loadAvg5M)) · \(String(format: "%.2f", $0.loadAvg15M))" }
            )

            // Memory
            statCard(
                label: "内存",
                value: current.map { _ in String(format: "%.1f%%", memPercent) },
                percent: memPercent,
                detail: current.map { "\(formatBytes($0.memoryUsedBytes)) / \(formatBytes($0.memoryTotalBytes))" }
            )

            // Disk
            statCard(
                label: "磁盘",
                value: current.map { _ in String(format: "%.1f%%", diskPercent) },
                percent: diskPercent,
                detail: current.map { "\(formatBytes($0.diskUsedBytes)) / \(formatBytes($0.diskTotalBytes))" }
            )

            // Indexed
            statCard(
                label: "已索引",
                value: current.map { "\(($0.indexedFiles ?? 0).formatted())" },
                percent: nil,
                detail: current.flatMap { c in
                    guard let db = c.dbSizeBytes else { return nil as String? }
                    let wal = c.dbWalSizeBytes ?? 0
                    return "DB \(formatBytes(db)) · WAL \(formatBytes(wal))"
                }
            )
        }
    }

    private func statCard(label: String, value: String?, percent: Double?, detail: String?) -> some View {
        VStack(spacing: 6) {
            if let value {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .fontDesign(.monospaced)
                    .foregroundStyle(percent != nil ? severityColor(percent!) : .secondary)
            } else {
                ProgressView()
                    .frame(height: 24)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)
                    if let percent {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(severityColor(percent))
                            .frame(width: geo.size.width * min(percent / 100, 1))
                    }
                }
            }
            .frame(height: 4)

            if let detail {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(AppTheme.Spacing.md)
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }

    // MARK: - History

    private var historySection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Header with range picker
            HStack {
                Text("历史趋势")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                HStack(spacing: 4) {
                    ForEach(rangeOptions, id: \.0) { (mins, label) in
                        Button {
                            rangeMinutes = mins
                            Task { await loadHistory() }
                        } label: {
                            Text(label)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(rangeMinutes == mins ? Color.primary.opacity(0.1) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(rangeMinutes == mins ? .primary : .tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Charts
            chartCard(title: "CPU %", data: snapshots.map { (ts($0), $0.cpuUsagePercent) }, min: 0, max: 100, color: .blue, unit: "%")
            chartCard(title: "内存", data: snapshots.map { (ts($0), Double($0.memoryUsedBytes)) }, min: 0, max: Double(current?.memoryTotalBytes ?? 1), color: .purple, unit: "GB")
            chartCard(title: "磁盘", data: snapshots.map { (ts($0), Double($0.diskUsedBytes)) }, min: 0, max: Double(current?.diskTotalBytes ?? 1), color: .cyan, unit: "GB")
            chartCard(title: "Load (1m)", data: snapshots.map { (ts($0), $0.loadAvg1M) }, min: 0, max: nil, color: .orange, unit: "")
        }
    }

    private func chartCard(title: String, data: [(Date, Double)], min: Double, max: Double?, color: Color, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            MiniChartView(data: data, rangeMinutes: rangeMinutes, minVal: min, maxVal: max, color: color, unit: unit)
                .frame(height: 120)
        }
        .padding(AppTheme.Spacing.md)
        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
    }

    // MARK: - Disks

    private var diskSection: some View {
        Group {
            if !disks.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    Text("磁盘详情")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(disks, id: \.mountPoint) { d in
                        VStack(spacing: 6) {
                            HStack {
                                Text(d.mountPoint)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(d.filesystem)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            ProgressView(value: Double(d.usedBytes), total: Double(d.totalBytes))
                                .tint(.secondary)

                            HStack {
                                Text("\(formatBytes(d.usedBytes)) 已用")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text("\(formatBytes(d.availableBytes)) 可用")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(AppTheme.Spacing.md)
                        .glassBackground(in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadCurrent() }
            group.addTask { await loadHistory() }
            group.addTask { await loadDisks() }
            group.addTask { await loadSystemInfo() }
        }
    }

    private func loadCurrent() async {
        do {
            let data = try await apiService.metrics.getCurrent()
            await MainActor.run { current = data }
        } catch {
            // Server may not have collected first snapshot yet, retry silently
        }
    }

    private func loadHistory() async {
        do {
            let data = try await apiService.metrics.getHistory(minutes: rangeMinutes)
            await MainActor.run { snapshots = data.snapshots }
        } catch {}
    }

    private func loadDisks() async {
        do {
            let data = try await apiService.metrics.getDiskDetails()
            await MainActor.run { disks = data.disks }
        } catch {}
    }

    private func loadSystemInfo() async {
        do {
            let data = try await apiService.metrics.getSystemInfo()
            await MainActor.run { systemInfo = data }
        } catch {}
    }

    // MARK: - Helpers

    private var memPercent: Double {
        guard let c = current, c.memoryTotalBytes > 0 else { return 0 }
        return Double(c.memoryUsedBytes) / Double(c.memoryTotalBytes) * 100
    }

    private var diskPercent: Double {
        guard let c = current, c.diskTotalBytes > 0 else { return 0 }
        return Double(c.diskUsedBytes) / Double(c.diskTotalBytes) * 100
    }

    private func severityColor(_ percent: Double) -> Color {
        if percent < 50 { return .green }
        if percent < 80 { return .orange }
        return .red
    }

    private static let tsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        return f
    }()

    private static let tsFormatterNoFrac: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return f
    }()

    private func ts(_ s: MetricsSnapshot) -> Date {
        Self.tsFormatter.date(from: s.timestamp)
            ?? Self.tsFormatterNoFrac.date(from: s.timestamp)
            ?? Date()
    }

    private func formatUptime(_ seconds: Int64) -> String {
        let d = seconds / 86400
        let h = (seconds % 86400) / 3600
        let m = (seconds % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1024 / 1024) }
        return String(format: "%.1f GB", Double(bytes) / 1024 / 1024 / 1024)
    }
}

// MARK: - Mini Chart (SwiftUI Canvas + Touch Tooltip)

private struct MiniChartView: View {
    let data: [(Date, Double)]
    let rangeMinutes: Int
    let minVal: Double
    let maxVal: Double?
    let color: Color
    let unit: String

    @State private var touchLocation: CGPoint? = nil
    @State private var tooltipInfo: (x: CGFloat, y: CGFloat, value: String, time: String)? = nil

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let xLabelFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let layout = chartLayout(size: size)

            ZStack(alignment: .topLeading) {
                // Chart canvas
                Canvas { ctx, size in
                    drawChart(ctx: ctx, size: size, layout: layout)
                }

                // Tooltip overlay
                if let tip = tooltipInfo {
                    VStack(spacing: 2) {
                        Text(tip.value)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .fontDesign(.monospaced)
                        Text(tip.time)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
                    .position(x: min(max(tip.x, 40), size.width - 40), y: max(tip.y - 20, 12))
                    .allowsHitTesting(false)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateTooltip(at: value.location, size: size, layout: layout)
                    }
                    .onEnded { _ in
                        tooltipInfo = nil
                    }
            )
        }
    }

    private struct ChartLayout {
        let pad: EdgeInsets
        let plotW: CGFloat
        let plotH: CGFloat
        let timeStart: Date
        let timeEnd: Date
        let rangeSec: Double
        let lo: Double
        let hi: Double
        let range: Double
        let visible: [(Date, Double)]
    }

    private func chartLayout(size: CGSize) -> ChartLayout {
        let pad = EdgeInsets(top: 8, leading: 36, bottom: 18, trailing: 4)
        let plotW = size.width - pad.leading - pad.trailing
        let plotH = size.height - pad.top - pad.bottom

        let now = Date()
        let rangeSec = Double(rangeMinutes * 60)
        let timeStart = now.addingTimeInterval(-rangeSec)

        let values = data.map(\.1)
        let lo = minVal
        let hi = maxVal ?? (values.isEmpty ? 100 : Swift.max(values.max()!, lo + 1))
        let range = hi - lo == 0 ? 1 : hi - lo

        let visible = data.filter { $0.0 >= timeStart && $0.0 <= now }

        return ChartLayout(pad: pad, plotW: plotW, plotH: plotH,
                           timeStart: timeStart, timeEnd: now, rangeSec: rangeSec,
                           lo: lo, hi: hi, range: range, visible: visible)
    }

    private func drawChart(ctx: GraphicsContext, size: CGSize, layout: ChartLayout) {
        let pad = layout.pad

        // Grid
        for i in 0...2 {
            let y = pad.top + layout.plotH * CGFloat(i) / 2
            var path = Path()
            path.move(to: CGPoint(x: pad.leading, y: y))
            path.addLine(to: CGPoint(x: size.width - pad.trailing, y: y))
            ctx.stroke(path, with: .color(.primary.opacity(0.06)), lineWidth: 1)
        }

        // Y labels
        let yFont = Font.system(size: 9).monospacedDigit()
        for (i, val) in [(0, layout.hi), (1, (layout.hi + layout.lo) / 2), (2, layout.lo)] {
            let y = pad.top + layout.plotH * CGFloat(i) / 2
            ctx.draw(Text(fmtVal(val)).font(yFont).foregroundStyle(.secondary.opacity(0.5)),
                     at: CGPoint(x: pad.leading - 4, y: y), anchor: .trailing)
        }

        // X labels
        let xFont = Font.system(size: 9)
        for i in 0...3 {
            let t = layout.timeStart.addingTimeInterval(layout.rangeSec * Double(i) / 3)
            let x = pad.leading + layout.plotW * CGFloat(i) / 3
            ctx.draw(Text(Self.xLabelFmt.string(from: t)).font(xFont).foregroundStyle(.secondary.opacity(0.5)),
                     at: CGPoint(x: x, y: size.height - 2), anchor: .bottom)
        }

        guard !layout.visible.isEmpty else { return }

        func px(_ d: Date) -> CGFloat {
            pad.leading + layout.plotW * CGFloat(d.timeIntervalSince(layout.timeStart) / layout.rangeSec)
        }
        func py(_ v: Double) -> CGFloat {
            pad.top + layout.plotH * (1 - CGFloat((v - layout.lo) / layout.range))
        }

        // Fill
        var fillPath = Path()
        fillPath.move(to: CGPoint(x: px(layout.visible.first!.0), y: pad.top + layout.plotH))
        for (d, v) in layout.visible { fillPath.addLine(to: CGPoint(x: px(d), y: py(v))) }
        fillPath.addLine(to: CGPoint(x: px(layout.visible.last!.0), y: pad.top + layout.plotH))
        fillPath.closeSubpath()
        ctx.fill(fillPath, with: .color(color.opacity(0.15)))

        // Line
        var linePath = Path()
        for (i, (d, v)) in layout.visible.enumerated() {
            let p = CGPoint(x: px(d), y: py(v))
            if i == 0 { linePath.move(to: p) }
            else { linePath.addLine(to: p) }
        }
        ctx.stroke(linePath, with: .color(color), lineWidth: 1.5)

        // Touch crosshair + dot
        if let tip = tooltipInfo {
            // Vertical line
            var crossPath = Path()
            crossPath.move(to: CGPoint(x: tip.x, y: pad.top))
            crossPath.addLine(to: CGPoint(x: tip.x, y: pad.top + layout.plotH))
            ctx.stroke(crossPath, with: .color(.primary.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            // Dot
            let dotRect = CGRect(x: tip.x - 4, y: tip.y - 4, width: 8, height: 8)
            ctx.fill(Path(ellipseIn: dotRect), with: .color(color))
        }
    }

    private func updateTooltip(at point: CGPoint, size: CGSize, layout: ChartLayout) {
        guard !layout.visible.isEmpty else { tooltipInfo = nil; return }

        func px(_ d: Date) -> CGFloat {
            layout.pad.leading + layout.plotW * CGFloat(d.timeIntervalSince(layout.timeStart) / layout.rangeSec)
        }
        func py(_ v: Double) -> CGFloat {
            layout.pad.top + layout.plotH * (1 - CGFloat((v - layout.lo) / layout.range))
        }

        var nearest: (Date, Double)? = nil
        var minDist: CGFloat = .greatestFiniteMagnitude
        for item in layout.visible {
            let dist = abs(px(item.0) - point.x)
            if dist < minDist { minDist = dist; nearest = item }
        }

        guard let nearest, minDist < 40 else { tooltipInfo = nil; return }
        tooltipInfo = (x: px(nearest.0), y: py(nearest.1),
                       value: fmtVal(nearest.1),
                       time: Self.timeFmt.string(from: nearest.0))
    }

    private func fmtVal(_ v: Double) -> String {
        if unit == "%" { return "\(Int(v))%" }
        if unit == "GB" { return String(format: "%.1fG", v / 1024 / 1024 / 1024) }
        return String(format: "%.1f", v)
    }
}
