//
//  ShareViewController.swift
//  ShareExtension
//
//  Share Extension 入口：
//  - Flow A（URL）：写入 App Group pending URL → 打开主 App 下载页（仅预填）
//  - Flow B（图/视频）：在 Extension 内完成上传 UI（大文件 background URLSession）
//

import UIKit
import UniformTypeIdentifiers
import SwiftUI

/// 分享内容快照
struct SharePayload: Equatable {
    var urls: [URL] = []
    var fileURLs: [URL] = []
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
                onOpenHostForURL: { [weak self] urlString in
                    self?.handOffURLToHost(urlString)
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
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                   let url = await loadFileURL(from: provider, type: UTType.fileURL.identifier) {
                    payload.fileURLs.append(url)
                    continue
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.video.identifier),
                   let url = await loadFileURL(from: provider, type: UTType.movie.identifier) {
                    payload.fileURLs.append(url)
                    continue
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                   let data = await loadData(from: provider, type: UTType.image.identifier) {
                    let name = suggestedName(for: provider, fallback: "share.jpg")
                    payload.imageItems.append(ShareImageItem(data: data, fileName: name))
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

    private func loadFileURL(from provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let url = item as? URL {
                    cont.resume(returning: Self.copyIntoStaging(url))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func loadData(from provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let data = item as? Data {
                    cont.resume(returning: data)
                } else if let image = item as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.95) {
                    cont.resume(returning: data)
                } else if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    cont.resume(returning: data)
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

    private func suggestedName(for provider: NSItemProvider, fallback: String) -> String {
        if let name = provider.suggestedName, !name.isEmpty {
            return name.contains(".") ? name : "\(name).jpg"
        }
        return fallback
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

    private static func copyIntoStaging(_ url: URL) -> URL? {
        let staging = AppGroup.uploadStagingURL ?? FileManager.default.temporaryDirectory
        let dest = staging.appendingPathComponent(url.lastPathComponent)
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return url
        }
    }

    // MARK: - Finish / handoff

    private func handOffURLToHost(_ urlString: String) {
        ShareBridge.setPendingDownloadURL(urlString)
        if let deepLink = ShareBridge.downloadDeepLink(url: urlString) {
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
    let onOpenHostForURL: (String) -> Void

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
                    ShareURLConfirmView(
                        urlString: first.absoluteString,
                        onConfirm: { onOpenHostForURL(first.absoluteString) },
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

struct ShareURLConfirmView: View {
    let urlString: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "link")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("打开 ReSourcer 下载页")
                .font(.title3.weight(.semibold))
            Text(urlString)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("将仅预填链接，不会自动检测或开始下载。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .padding(.top, 40)
        .navigationTitle("分享链接")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("打开", action: onConfirm)
            }
        }
    }
}
