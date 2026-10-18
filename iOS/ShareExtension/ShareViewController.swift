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
import Photos

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
                Self.writeEnrichDebug(
                    "provider types=\(provider.registeredTypeIdentifiers.joined(separator: "|")) suggested=\(provider.suggestedName ?? "-")"
                )
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await loadURL(from: provider), !url.isFileURL {
                    payload.urls.append(url)
                    continue
                }

                let hasImage = Self.imageTypeIdentifiers.contains {
                    provider.hasItemConformingToTypeIdentifier($0)
                }
                let hasVideo = Self.videoTypeIdentifiers.contains {
                    provider.hasItemConformingToTypeIdentifier($0)
                }
                let isLivePhotoUTI = Self.livePhotoTypeIdentifiers.contains {
                    provider.hasItemConformingToTypeIdentifier($0)
                }
                    || provider.registeredTypeIdentifiers.contains(where: {
                        $0.lowercased().contains("live-photo") || $0.lowercased().contains("livephoto")
                    })

                // 实况照片：同一 provider 常同时符合 image + movie（或 com.apple.live-photo）。
                // 必须两者都取，且静帧优先 public.heic，不能先取视频后 continue 丢掉 HEIC。
                if isLivePhotoUTI || (hasImage && hasVideo) {
                    if let still = await loadOriginalMediaFile(
                        from: provider,
                        preferredTypes: Self.imageTypeIdentifiers
                    ) {
                        payload.fileURLs.append(still)
                    } else if let raw = await loadOriginalImageBytes(from: provider) {
                        payload.imageItems.append(raw)
                    }
                    if let video = await loadOriginalMediaFile(
                        from: provider,
                        preferredTypes: Self.videoTypeIdentifiers
                    ) {
                        payload.fileURLs.append(video)
                    } else if let video = await loadLivePhotoPairedMovie(from: provider) {
                        // Photos 只声明 com.apple.live-photo + heic，不单独声明 movie UTI
                        payload.fileURLs.append(video)
                    }
                    continue
                }

                // 纯视频：优先原始文件表示（HEVC/MOV），勿经转码路径
                if hasVideo,
                   let staged = await loadOriginalMediaFile(
                    from: provider,
                    preferredTypes: Self.videoTypeIdentifiers
                   ) {
                    payload.fileURLs.append(staged)
                    continue
                }

                // 纯图片：优先 HEIC/HEIF；实况分享有时只声明 image，仍尝试同 provider 拉 movie
                if hasImage,
                   let staged = await loadOriginalMediaFile(
                    from: provider,
                    preferredTypes: Self.imageTypeIdentifiers
                   ) {
                    payload.fileURLs.append(staged)
                    if let video = await loadOriginalMediaFile(
                        from: provider,
                        preferredTypes: Self.videoTypeIdentifiers
                    ) {
                        payload.fileURLs.append(video)
                    }
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
        // Photos Share Sheet 对实况常只给静帧 provider；补拉 PairedVideo（需相册权限）
        return await enrichLivePhotoPairedVideos(payload)
    }

    /// 当已有 HEIC/HEIF 静帧但缺少同 stem 的 MOV 时，从 Photos 库按原文件名找回 PairedVideo。
    private func enrichLivePhotoPairedVideos(_ payload: SharePayload) async -> SharePayload {
        var result = payload
        let existingNames = Set(result.fileURLs.map { $0.lastPathComponent.lowercased() })
        let stillURLs = result.fileURLs.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "heic" || ext == "heif"
        }
        guard !stillURLs.isEmpty else { return result }

        let status = await requestPhotoLibraryAccessIfNeeded()
        let photosOK = status == .authorized || status == .limited
        if !photosOK {
            Self.writeEnrichDebug("photoAuth=\(status.rawValue) → AppGroup companion fallback")
        }

        for stillURL in stillURLs {
            let stillName = stillURL.lastPathComponent
            let stem = (stillName as NSString).deletingPathExtension
            let movName = "\(stem).MOV"
            let movNameLower = movName.lowercased()
            if existingNames.contains(movNameLower) || existingNames.contains("\(stem.lowercased()).mov") {
                continue
            }
            var paired: URL?
            var pairedSource = "none"
            if photosOK {
                paired = await loadPairedVideoFromPhotos(matchingStillFileName: stillName)
                if paired != nil { pairedSource = "photos-pairedVideo" }
            }
            // 仅当主 App 显式写入 App Group 开关时才用 CI companion（模拟器 TCC 挡 Photos 时）。
            // 真机 / 未开开关：禁止 companion，避免把探针路径当成 Photos→Share 验收。
            if paired == nil, Self.e2eCompanionAllowed {
                paired = Self.loadE2ECompanionMOV(forStill: stillURL)
                if paired != nil { pairedSource = "e2e-companion" }
            }
            if let paired,
               let staged = Self.copyIntoStaging(paired, preferredName: movName) {
                result.fileURLs.append(staged)
                let bytes = (try? staged.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                Self.writeEnrichDebug(
                    "pairedOK source=\(pairedSource) still=\(stillName) mov=\(movName) bytes=\(bytes)"
                )
            } else {
                Self.writeEnrichDebug(
                    "pairedNil still=\(stillName) photosOK=\(photosOK) companionAllowed=\(Self.e2eCompanionAllowed)"
                )
            }
        }
        return result
    }

    /// App Group 开关：主 App 在 E2E 下写入 `e2e_allow_live_companion=1` 后才允许 companion MOV。
    nonisolated private static var e2eCompanionAllowed: Bool {
        let defaults = AppGroup.defaults
        return defaults.string(forKey: "e2e_allow_live_companion") == "1"
            || defaults.bool(forKey: "e2e_allow_live_companion")
    }

    /// 模拟器 Share Extension Photos 授权常 denied：用主 App 预置的 Content Identifier / IMG_LIVE 配对 MOV。
    nonisolated private static func loadE2ECompanionMOV(forStill stillURL: URL) -> URL? {
        guard e2eCompanionAllowed else { return nil }
        guard let dir = AppGroup.e2eLiveCompanionDirectoryURL else { return nil }
        let contentId = heicContentIdentifier(from: stillURL)
        let stillStem = normalizedPhotoStem(stillURL.lastPathComponent)
        let candidates: [URL] = [
            contentId.map { dir.appendingPathComponent("\($0).MOV") },
            contentId.map { dir.appendingPathComponent("\($0).mov") },
            dir.appendingPathComponent("IMG_LIVE.MOV"),
            dir.appendingPathComponent("IMG_LIVE.mov"),
        ].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if contentId != nil || stillStem.contains("img_live") {
                writeEnrichDebug("e2eCompanion hit=\(url.lastPathComponent) still=\(stillURL.lastPathComponent)")
                return url
            }
        }
        return nil
    }

    /// 从 HEIC 字节里扫 Apple Content Identifier（UUID 形）
    nonisolated private static func heicContentIdentifier(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.count > 64 else { return nil }
        let uuidPattern = try? NSRegularExpression(
            pattern: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
        )
        let asString = String(decoding: data.prefix(256 * 1024), as: UTF8.self)
        let range = NSRange(asString.startIndex..<asString.endIndex, in: asString)
        if let match = uuidPattern?.firstMatch(in: asString, options: [], range: range),
           let swiftRange = Range(match.range, in: asString) {
            return String(asString[swiftRange]).uppercased()
        }
        return nil
    }

    nonisolated private static func writeEnrichDebug(_ line: String) {
        guard let dir = AppGroup.containerURL else { return }
        let url = dir.appendingPathComponent("live-enrich-debug.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) \(line)\n"
        if let data = text.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// Share Sheet 常把 `IMG_LIVE.HEIC` 改成 `IMG_LIVE(1).HEIC` 或 `UUID-IMG_LIVE.HEIC`。
    nonisolated private static func normalizedPhotoStem(_ fileNameOrStem: String) -> String {
        let asNS = fileNameOrStem as NSString
        var stem = asNS.pathExtension.isEmpty ? fileNameOrStem : asNS.deletingPathExtension
        if let regex = try? NSRegularExpression(pattern: #"\s*\(\d+\)$"#) {
            let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)
            stem = regex.stringByReplacingMatches(in: stem, options: [], range: range, withTemplate: "")
        }
        return stem.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `0F5B5857-IMG_LIVE` ↔ `IMG_LIVE`；`IMG_LIVE(1)` ↔ `IMG_LIVE`。
    nonisolated private static func photoStemsMatch(_ shareStem: String, _ libraryStem: String) -> Bool {
        if shareStem == libraryStem { return true }
        if shareStem.hasSuffix("-" + libraryStem) { return true }
        if libraryStem.hasSuffix("-" + shareStem) { return true }
        // 去重后缀已在 normalizedPhotoStem 去掉；再容忍 contains
        if shareStem.contains(libraryStem) && libraryStem.count >= 4 { return true }
        if libraryStem.contains(shareStem) && shareStem.count >= 4 { return true }
        return false
    }

    private func requestPhotoLibraryAccessIfNeeded() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        // 已授权 / 有限访问：直接用
        if current == .authorized || current == .limited { return current }
        // notDetermined：弹系统框；denied 时再请求一次（模拟器 TCC 与签名身份偶发不同步）
        return await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                cont.resume(returning: status)
            }
        }
    }

    /// 在相册中找 originalFilename 匹配的实况静帧，写出其 PairedVideo 到临时文件。
    private func loadPairedVideoFromPhotos(matchingStillFileName stillName: String) async -> URL? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let opts = PHFetchOptions()
                opts.includeHiddenAssets = false
                opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let assets = PHAsset.fetchAssets(with: .image, options: opts)
                let target = stillName.lowercased()
                let targetStem = Self.normalizedPhotoStem(stillName)
                var matched: PHAsset?
                var liveCandidates: [PHAsset] = []
                assets.enumerateObjects { asset, _, stop in
                    let resources = PHAssetResource.assetResources(for: asset)
                    // 不依赖 mediaSubtypes.photoLive：simctl addmedia 的配对常无该标记，
                    // 但仍有 .photo + .pairedVideo 资源。
                    let hasPaired = resources.contains { $0.type == .pairedVideo }
                    guard hasPaired else { return }
                    liveCandidates.append(asset)
                    let hasStill = resources.contains { r in
                        let n = r.originalFilename.lowercased()
                        let nStem = Self.normalizedPhotoStem(n)
                        let isPhotoResource = r.type == .photo || r.type == .fullSizePhoto
                        let nameHit = n == target || Self.photoStemsMatch(targetStem, nStem)
                        return nameHit
                            && (isPhotoResource
                                || n.hasSuffix(".heic")
                                || n.hasSuffix(".heif")
                                || n.hasSuffix(".jpg")
                                || n.hasSuffix(".jpeg"))
                    }
                    if hasStill {
                        matched = asset
                        stop.pointee = true
                    }
                }
                // 名称对不上时：取最近一张带 PairedVideo 的资源（单张分享 / 模拟器）
                if matched == nil {
                    matched = liveCandidates.first
                }
                guard let asset = matched else {
                    cont.resume(returning: nil)
                    return
                }
                let resources = PHAssetResource.assetResources(for: asset)
                guard let paired = resources.first(where: { $0.type == .pairedVideo }) else {
                    cont.resume(returning: nil)
                    return
                }
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString)_\(paired.originalFilename)")
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true
                PHAssetResourceManager.default().writeData(for: paired, toFile: temp, options: options) { error in
                    if error != nil {
                        cont.resume(returning: nil)
                    } else {
                        cont.resume(returning: temp)
                    }
                }
            }
        }
    }

    /// 图片 UTType：具体格式优先于泛型 `public.image`（HEIC 必须排在 JPEG 前）
    private static let imageTypeIdentifiers: [String] = [
        UTType.heic.identifier,
        UTType.heif.identifier,
        "public.heic",
        "public.heif",
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

    /// 实况照片容器 UTI（系统可能单独声明）
    private static let livePhotoTypeIdentifiers: [String] = [
        "com.apple.live-photo",
        "com.apple.private.live-photo",
        "com.apple.private.live-photo-complete",
        "com.apple.live-photo-bundle",
    ]

    /// Photos Share 常只给 `com.apple.live-photo`（无 public.movie）。
    /// 尝试多种表示拿到包内 MOV；失败再试 PHLivePhoto。
    private func loadLivePhotoPairedMovie(from provider: NSItemProvider) async -> URL? {
        for typeId in Self.livePhotoTypeIdentifiers {
            let has = provider.hasItemConformingToTypeIdentifier(typeId)
                || provider.registeredTypeIdentifiers.contains(typeId)
            guard has else { continue }
            Self.writeEnrichDebug("tryLive type=\(typeId)")
            if let url = await loadFileRepresentation(from: provider, type: typeId) {
                Self.writeEnrichDebug("livePhotoFile type=\(typeId) path=\(url.lastPathComponent) isDir=\(url.hasDirectoryPath)")
                if let mov = Self.findMovieBesideOrInside(url) {
                    return mov
                }
            }
            if let data = await loadDataRepresentationOnly(from: provider, type: typeId), !data.isEmpty {
                Self.writeEnrichDebug("livePhotoData type=\(typeId) bytes=\(data.count)")
                // 少数系统把 live-photo 打成 zip/包字节；先落盘再扫
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).livephoto")
                try? data.write(to: tmp)
                if let mov = Self.findMovieBesideOrInside(tmp) {
                    return mov
                }
            }
        }
        // 再盲试 movie UTI（有时未出现在 registeredTypeIdentifiers 仍可 load）
        for typeId in Self.videoTypeIdentifiers {
            if let url = await loadFileRepresentation(from: provider, type: typeId) {
                Self.writeEnrichDebug("blindMovie type=\(typeId) name=\(url.lastPathComponent)")
                return url
            }
        }
        if provider.canLoadObject(ofClass: PHLivePhoto.self) {
            _ = await loadMovieViaPHLivePhoto(from: provider)
        }
        return nil
    }

    private func loadMovieViaPHLivePhoto(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: PHLivePhoto.self) { object, error in
                guard object is PHLivePhoto else {
                    Self.writeEnrichDebug("PHLivePhoto load fail err=\(String(describing: error))")
                    cont.resume(returning: nil)
                    return
                }
                // 公共 API 无法从 PHLivePhoto 直接拆 MOV；标记后回退 enrich
                Self.writeEnrichDebug("PHLivePhoto object loaded (no public MOV export)")
                cont.resume(returning: nil)
            }
        }
    }

    /// 在 live-photo 文件/目录旁找 .mov/.mp4
    nonisolated private static func findMovieBesideOrInside(_ url: URL) -> URL? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        let candidates: [URL]
        if isDir.boolValue {
            candidates = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        } else {
            let parent = url.deletingLastPathComponent()
            candidates = ((try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []) + [url]
        }
        let movieExts = Set(["mov", "mp4", "m4v", "qt"])
        if let hit = candidates.first(where: { movieExts.contains($0.pathExtension.lowercased()) }) {
            return copyIntoStaging(hit, preferredName: hit.lastPathComponent)
        }
        // 单文件 live-photo 有时是 .pvt / 无扩展包：再扫一层子目录
        for child in candidates where child.hasDirectoryPath {
            if let nested = findMovieBesideOrInside(child) { return nested }
        }
        return nil
    }

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
        // 冷启动时主 App 读 App Group：先刷盘再拉起，避免竞态丢 pending
        AppGroup.defaults.synchronize()

        guard let deepLink = ShareBridge.downloadDeepLink(
            url: handoff.url,
            serverId: handoff.serverId,
            sourceFolder: handoff.sourceFolder
        ) else {
            finishExtension()
            return
        }

        // 先发起打开，再延后 completeRequest；立刻结束扩展会取消尚未完成的 openURL
        openHostURL(deepLink) { [weak self] in
            self?.finishExtension()
        }
    }

    /// 拉起宿主 App（自定义 scheme）。参考国内分享扩展常见做法：
    /// 1) UIApplication.open  2) responder `openURL:`  3) `extensionContext.open`
    /// 禁止在 open 完成前调用 `completeRequest`。
    private func openHostURL(_ url: URL, completion: @escaping @Sendable () -> Void) {
        if openURLViaSharedApplication(url) || openURLViaResponderChain(url) {
            // 给系统一点时间切换到宿主；过早 complete 会导致「写了 pending 但不跳转」
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                completion()
            }
            return
        }

        // 官方 API：对含自定义 URL scheme 的宿主 App，部分系统版本可用
        if let context = extensionContext {
            context.open(url) { [self] success in
                if success {
                    completion()
                    return
                }
                // open 失败时仍再试一次响应链（部分机型第一次链未就绪）
                if self.openURLViaSharedApplication(url) || self.openURLViaResponderChain(url) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        completion()
                    }
                } else {
                    // pending 已写入 App Group：结束扩展，用户手动打开仍可消费；此处不谎称已拉起
                    completion()
                }
            }
            return
        }

        completion()
    }

    /// 经 KVC / perform 取 `UIApplication.shared` 再 `open`（扩展内无直接 shared API；微信/QQ 同类路径）
    @discardableResult
    private func openURLViaSharedApplication(_ url: URL) -> Bool {
        let application = resolveSharedApplication()
        guard let application else { return false }
        application.open(url, options: [:], completionHandler: nil)
        return true
    }

    private func resolveSharedApplication() -> UIApplication? {
        if let app = UIApplication.value(forKeyPath: "sharedApplication") as? UIApplication {
            return app
        }
        let selector = NSSelectorFromString("sharedApplication")
        guard UIApplication.responds(to: selector),
              let unmanaged = UIApplication.perform(selector),
              let app = unmanaged.takeUnretainedValue() as? UIApplication else {
            return nil
        }
        return app
    }

    /// 沿 responder / window 链找到 UIApplication，或对响应 `openURL:` 的对象执行选择子
    @discardableResult
    private func openURLViaResponderChain(_ url: URL) -> Bool {
        let openSelector = sel_registerName("openURL:")
        var opened = false

        func walk(_ start: UIResponder?) {
            var responder = start
            while let cur = responder {
                if let application = cur as? UIApplication {
                    application.open(url, options: [:], completionHandler: nil)
                    opened = true
                    return
                }
                if cur.responds(to: openSelector) {
                    cur.perform(openSelector, with: url)
                    opened = true
                    // 继续向上：部分链上会有「假响应」对象，尽量打到 UIApplication
                }
                responder = cur.next
            }
        }

        walk(self)
        if !opened {
            walk(view.window)
        }
        if !opened, let parent = parent {
            walk(parent)
        }
        return opened
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
