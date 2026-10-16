//
//  ShareViewController.swift
//  ShareExtension
//
//  Share Extension 入口：
//  - Flow A（URL）：写入 App Group pending URL → 打开主 App 下载页（仅预填）
//  - Flow B（图/视频）：在 Extension 内完成上传 UI（大文件 background URLSession）
//
//  媒体加载原则：优先 NSItemProvider.loadFileRepresentation，按原始 UTType 拷贝字节。
//  禁止 UIImage → jpegData 重编码（会把 HEIC 变成 JPEG 并丢掉 EXIF/GPS）。
//

import UIKit
import UniformTypeIdentifiers
import SwiftUI

/// 分享内容快照
struct SharePayload: Equatable {
    var urls: [URL] = []
    var fileURLs: [URL] = []
    /// 仅当无法拿到文件 URL、但仍有原始字节时使用（不经 UIImage 重编码）
    var imageItems: [ShareImageItem] = []

    var hasMedia: Bool { !fileURLs.isEmpty || !imageItems.isEmpty }
}

struct ShareImageItem: Equatable {
    let data: Data
    let fileName: String

    static func == (lhs: ShareImageItem, rhs: ShareImageItem) -> Bool {
        lhs.fileName == rhs.fileName && lhs.data.count == rhs.data.count
    }
}

@objc(ShareViewController)
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        let payload = await loadSharedItems()
        await MainActor.run {
            let root = ShareRootView(
                payload: payload,
                onFinish: { [weak self] in self?.finishExtension() },
                onCancel: { [weak self] in self?.cancelExtension() },
                onOpenHostForURL: { [weak self] handoff in
                    self?.handOffURLToHost(handoff)
                }
            )
            let host = UIHostingController(rootView: root)
            addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            host.didMove(toParent: self)
        }
    }

    // MARK: - Load attachments

    private func loadSharedItems() async -> SharePayload {
        var payload = SharePayload()
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return payload
        }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await loadURL(from: provider), !url.isFileURL {
                    payload.urls.append(url)
                    continue
                }

                // 视频：优先原始文件表示（HEVC/MOV 等），勿经转码路径
                if let staged = await loadOriginalMediaFile(
                    from: provider,
                    preferredTypes: Self.videoTypeIdentifiers
                ) {
                    payload.fileURLs.append(staged)
                    continue
                }

                // 图片：优先 HEIC/HEIF 等具体类型的文件表示，再回退通用 image
                if let staged = await loadOriginalMediaFile(
                    from: provider,
                    preferredTypes: Self.imageTypeIdentifiers
                ) {
                    payload.fileURLs.append(staged)
                    continue
                }

                // 通用 fileURL（非图/视频附件）
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                   let url = await loadOriginalFileURL(from: provider, type: UTType.fileURL.identifier) {
                    payload.fileURLs.append(url)
                    continue
                }

                // 最后：原始字节（仍禁止 UIImage 重编码）
                if let raw = await loadOriginalImageBytes(from: provider) {
                    payload.imageItems.append(raw)
                    continue
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = await loadString(from: provider),
                   let extracted = extractHTTPURL(from: text) {
                    payload.urls.append(extracted)
                }
            }
        }
        return payload
    }

    /// 图片 UTType：具体格式优先于泛型 `public.image`
    private static let imageTypeIdentifiers: [String] = [
        UTType.heic.identifier,
        UTType.heif.identifier,
        UTType.jpeg.identifier,
        UTType.png.identifier,
        UTType.gif.identifier,
        UTType.webP.identifier,
        UTType.tiff.identifier,
        UTType.image.identifier,
    ]

    /// 视频 UTType：QuickTime / MPEG-4 优先于泛型 movie/video
    private static let videoTypeIdentifiers: [String] = [
        UTType.quickTimeMovie.identifier,
        UTType.mpeg4Movie.identifier,
        UTType.movie.identifier,
        UTType.video.identifier,
        UTType.audiovisualContent.identifier,
    ]

    /// 用 `loadFileRepresentation` 拿到系统提供的原始临时文件并拷进 staging
    private func loadOriginalMediaFile(
        from provider: NSItemProvider,
        preferredTypes: [String]
    ) async -> URL? {
        for typeId in preferredTypes {
            guard provider.hasItemConformingToTypeIdentifier(typeId) else { continue }
            if let url = await loadFileRepresentation(from: provider, type: typeId) {
                return url
            }
        }
        return nil
    }

    private func loadFileRepresentation(from provider: NSItemProvider, type: String) async -> URL? {
        // 先取出 Sendable 值，避免在 @Sendable 回调里捕获 NSItemProvider（Xcode 26.6 complete concurrency）
        let suggestedName = provider.suggestedName
        return await withCheckedContinuation { cont in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url else {
                    cont.resume(returning: nil)
                    return
                }
                // 回调返回后系统会删除临时文件，必须在此同步拷贝
                let preferred = Self.preferredFileName(
                    suggestedName: suggestedName,
                    sourceURL: url,
                    typeIdentifier: type
                )
                cont.resume(returning: Self.copyIntoStaging(url, preferredName: preferred))
            }
        }
    }

    private func loadOriginalFileURL(from provider: NSItemProvider, type: String) async -> URL? {
        // 先 file representation，再 loadItem(URL)
        if let viaRep = await loadFileRepresentation(from: provider, type: type) {
            return viaRep
        }
        let suggestedName = provider.suggestedName
        return await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let url = item as? URL {
                    let preferred = Self.preferredFileName(
                        suggestedName: suggestedName,
                        sourceURL: url,
                        typeIdentifier: type
                    )
                    cont.resume(returning: Self.copyIntoStaging(url, preferredName: preferred))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// 原始字节回退：`loadDataRepresentation` / Data / file URL；绝不 UIImage→JPEG
    private func loadOriginalImageBytes(from provider: NSItemProvider) async -> ShareImageItem? {
        for typeId in Self.imageTypeIdentifiers {
            guard provider.hasItemConformingToTypeIdentifier(typeId) else { continue }
            if let data = await loadDataRepresentation(from: provider, type: typeId) {
                let name = Self.preferredFileName(
                    suggestedName: provider.suggestedName,
                    sourceURL: nil,
                    typeIdentifier: typeId,
                    data: data
                )
                return ShareImageItem(data: data, fileName: name)
            }
        }
        return nil
    }

    private func loadDataRepresentation(from provider: NSItemProvider, type: String) async -> Data? {
        if let data = await loadDataRepresentationOnly(from: provider, type: type), !data.isEmpty {
            return data
        }
        // 再退到 loadItem，但只接受 Data / file URL 原始字节（忽略 UIImage）
        return await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let data = item as? Data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if let url = item as? URL, let data = try? Data(contentsOf: url), !data.isEmpty {
                    cont.resume(returning: data)
                } else {
                    // 刻意忽略 UIImage：jpegData 会毁掉 HEIC/EXIF
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func loadDataRepresentationOnly(from provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { cont in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                cont.resume(returning: data)
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    cont.resume(returning: url)
                } else if let data = item as? Data,
                          let s = String(data: data, encoding: .utf8),
                          let url = URL(string: s) {
                    cont.resume(returning: url)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func loadString(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                cont.resume(returning: item as? String)
            }
        }
    }

    private func extractHTTPURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: trimmed), let scheme = u.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return u
        }
        let pattern = #"https?://[^\s]+"#
        if let range = trimmed.range(of: pattern, options: .regularExpression) {
            return URL(string: String(trimmed[range]))
        }
        return nil
    }

    // MARK: - Naming / staging

    /// 优先原始文件名；否则按 UTType / 魔数补扩展名（默认不再强行 .jpg）
    /// `nonisolated`: NSItemProvider 回调不在 MainActor；UIViewController 默认隔离会触发 sending risks data races。
    /// 只接收已提取的 `suggestedName`（Sendable），勿把 `NSItemProvider` 传入回调。
    nonisolated private static func preferredFileName(
        suggestedName: String?,
        sourceURL: URL?,
        typeIdentifier: String,
        data: Data? = nil
    ) -> String {
        if let sourceURL {
            let last = sourceURL.lastPathComponent
            if !last.isEmpty, last != "/", last.contains(".") {
                return last
            }
        }
        if let suggested = suggestedName, !suggested.isEmpty {
            if suggested.contains(".") {
                return suggested
            }
            let ext = fileExtension(
                forTypeIdentifier: typeIdentifier,
                data: data,
                sourceURL: sourceURL
            )
            return "\(suggested).\(ext)"
        }
        let ext = fileExtension(
            forTypeIdentifier: typeIdentifier,
            data: data,
            sourceURL: sourceURL
        )
        return "share.\(ext)"
    }

    nonisolated private static func fileExtension(
        forTypeIdentifier typeId: String,
        data: Data?,
        sourceURL: URL?
    ) -> String {
        if let sourceURL {
            let ext = sourceURL.pathExtension
            if !ext.isEmpty { return ext.lowercased() }
        }
        if let ut = UTType(typeId), let preferred = ut.preferredFilenameExtension {
            return preferred
        }
        if let data, let fromMagic = extensionFromMagic(data) {
            return fromMagic
        }
        switch typeId {
        case UTType.heic.identifier, UTType.heif.identifier: return "heic"
        case UTType.jpeg.identifier: return "jpg"
        case UTType.png.identifier: return "png"
        case UTType.gif.identifier: return "gif"
        case UTType.webP.identifier: return "webp"
        case UTType.tiff.identifier: return "tiff"
        case UTType.quickTimeMovie.identifier: return "mov"
        case UTType.mpeg4Movie.identifier: return "mp4"
        default: return "bin"
        }
    }

    /// 根据文件头推断扩展名（用于无文件名时）
    nonisolated private static func extensionFromMagic(_ data: Data) -> String? {
        guard data.count >= 12 else { return nil }
        // JPEG
        if data[0] == 0xFF, data[1] == 0xD8, data[2] == 0xFF { return "jpg" }
        // PNG
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        // GIF
        if let s = String(data: data.prefix(6), encoding: .ascii), s.hasPrefix("GIF") { return "gif" }
        // ISO BMFF (HEIC/HEIF/MP4/MOV): ....ftypXXXX
        if data.count >= 12 {
            let ftyp = data.subdata(in: 4..<8)
            if String(data: ftyp, encoding: .ascii) == "ftyp" {
                let brand = String(data: data.subdata(in: 8..<12), encoding: .ascii)?.lowercased() ?? ""
                if brand.contains("heic") || brand.contains("heif") || brand == "mif1" || brand == "msf1" {
                    return "heic"
                }
                if brand == "qt  " { return "mov" }
                if brand.contains("mp4") || brand == "isom" || brand == "M4V " {
                    return "mp4"
                }
            }
        }
        return nil
    }

    nonisolated private static func copyIntoStaging(_ url: URL, preferredName: String? = nil) -> URL? {
        let staging = AppGroup.uploadStagingURL ?? FileManager.default.temporaryDirectory
        let name = preferredName?.isEmpty == false ? preferredName! : url.lastPathComponent
        // 优先保留原始文件名；仅冲突时加短前缀
        var dest = staging.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            dest = staging.appendingPathComponent("\(UUID().uuidString.prefix(8))-\(name)")
        }
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    // MARK: - Finish / handoff

    private func handOffURLToHost(_ handoff: SharePendingDownloadHandoff) {
        ShareBridge.setPendingDownload(handoff)
        // 记住链接分享的目标（与媒体上传共用 lastDestination）
        if let serverId = handoff.serverId, let source = handoff.sourceFolder, !source.isEmpty {
            ShareBridge.saveLastDestination(
                ShareDestinationPreference(serverId: serverId, sourceFolder: source, subfolder: "")
            )
        }
        if let deepLink = ShareBridge.downloadDeepLink(
            url: handoff.url,
            serverId: handoff.serverId,
            sourceFolder: handoff.sourceFolder
        ) {
            openHostURL(deepLink)
        }
        finishExtension()
    }

    private func openHostURL(_ url: URL) {
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let cur = responder {
            if cur.responds(to: selector) {
                cur.perform(selector, with: url)
                return
            }
            responder = cur.next
        }
    }

    private func finishExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func cancelExtension() {
        let error = NSError(domain: "ShareExtension", code: NSUserCancelledError, userInfo: nil)
        extensionContext?.cancelRequest(withError: error)
    }
}

// MARK: - Root SwiftUI

struct ShareRootView: View {
    let payload: SharePayload
    let onFinish: () -> Void
    let onCancel: () -> Void
    let onOpenHostForURL: (SharePendingDownloadHandoff) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if payload.hasMedia {
                    ShareUploadView(
                        fileURLs: payload.fileURLs,
                        imageItems: payload.imageItems,
                        onFinish: onFinish,
                        onCancel: onCancel
                    )
                } else if let first = payload.urls.first {
                    ShareURLDestinationView(
                        urlString: first.absoluteString,
                        onConfirm: { handoff in onOpenHostForURL(handoff) },
                        onCancel: onCancel
                    )
                } else {
                    ContentUnavailableView(
                        "无法分享",
                        systemImage: "exclamationmark.triangle",
                        description: Text("未识别到链接或媒体文件")
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭", action: onCancel)
                        }
                    }
                }
            }
        }
    }
}

/// Flow A：选服务器（名称+URL）与源文件夹后打开主 App 下载页（仅预填）
struct ShareURLDestinationView: View {
    let urlString: String
    let onConfirm: (SharePendingDownloadHandoff) -> Void
    let onCancel: () -> Void

    @State private var servers: [Server] = []
    @State private var selectedServerId: String = ""
    @State private var sourceFolders: [String] = []
    @State private var selectedSource: String = ""
    @State private var isLoadingMeta = false
    @State private var errorMessage: String?

    private var selectedServer: Server? {
        servers.first { $0.id == selectedServerId }
    }

    var body: some View {
        Form {
            Section("链接") {
                Text(urlString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("将打开主 App 下载页并预填链接，不会自动检测或开始下载。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("目标") {
                Picker("服务器", selection: $selectedServerId) {
                    ForEach(servers) { server in
                        Text(ShareBridge.sharePickerLabel(for: server))
                            .tag(server.id)
                    }
                }
                .accessibilityIdentifier("shareURLServerPicker")
                .onChange(of: selectedServerId) { _, _ in
                    Task { await reloadSources() }
                }

                if sourceFolders.isEmpty {
                    Text(isLoadingMeta ? "加载源文件夹…" : (errorMessage ?? "无可用源文件夹"))
                        .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                        .accessibilityIdentifier("shareURLSourceFoldersStatus")
                } else {
                    Picker("源文件夹", selection: $selectedSource) {
                        ForEach(sourceFolders, id: \.self) { path in
                            Text(displayName(for: path)).tag(path)
                        }
                    }
                    .accessibilityIdentifier("shareURLSourcePicker")
                }
            }

            Section {
                Button {
                    guard let server = selectedServer, !selectedSource.isEmpty else { return }
                    onConfirm(
                        SharePendingDownloadHandoff(
                            url: urlString,
                            serverId: server.id,
                            sourceFolder: selectedSource
                        )
                    )
                } label: {
                    HStack {
                        Spacer()
                        Text("打开下载页")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(selectedServer == nil || selectedSource.isEmpty)
                .accessibilityIdentifier("shareURLOpenDownload")
            }
        }
        .navigationTitle("分享链接")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消", action: onCancel)
            }
        }
        .task { await bootstrap() }
    }

    private func displayName(for path: String) -> String {
        path.components(separatedBy: "/").last ?? path
    }

    private func bootstrap() async {
        servers = ShareBridge.loadServers()
        let last = ShareBridge.loadLastDestination()
        if let last, servers.contains(where: { $0.id == last.serverId }) {
            selectedServerId = last.serverId
        } else if let current = ShareBridge.currentServer() {
            selectedServerId = current.id
        } else {
            selectedServerId = servers.first?.id ?? ""
        }
        await reloadSources()
        if let last, last.serverId == selectedServerId,
           sourceFolders.contains(last.sourceFolder) {
            selectedSource = last.sourceFolder
        }
    }

    private func reloadSources() async {
        guard let server = selectedServer else {
            sourceFolders = []
            selectedSource = ""
            return
        }
        if server.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceFolders = []
            selectedSource = ""
            errorMessage = "无法读取服务器凭证：请先在主 App 打开一次以同步 App Group / Keychain"
            isLoadingMeta = false
            return
        }
        isLoadingMeta = true
        errorMessage = nil
        defer { isLoadingMeta = false }
        do {
            let paths = try await ShareUploadClient.loadSourceFoldersTryingCandidates(for: server)
            sourceFolders = paths
            if selectedSource.isEmpty || !paths.contains(selectedSource) {
                selectedSource = paths.first ?? ""
            }
        } catch {
            errorMessage = "加载源文件夹失败：\(error.localizedDescription)"
            sourceFolders = []
        }
    }
}
