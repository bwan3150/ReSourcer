//
//  LivePhotoPreviewContent.swift
//  ReSourcer
//
//  实况照片预览：PHLivePhotoView（按住播放）；合成失败时回退静帧+MOV。
//  LIVE 标记：安全区下方、左上（对齐系统相册），Liquid Glass。
//

import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import AVKit
import UIKit

/// 实况照片查看：下载静帧 + 配对视频 → PHLivePhoto；失败则静帧+视频叠加
struct LivePhotoPreviewContent: View {

    let file: FileInfo
    let apiService: APIService
    let onTap: () -> Void
    let onSwipe: (Int) -> Bool

    @State private var livePhoto: PHLivePhoto?
    @State private var fallbackStill: UIImage?
    @State private var fallbackVideoURL: URL?
    @State private var loadFailed = false
    @State private var isPlayingFallback = false
    @State private var scale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 媒体：强制占满 GeometryReader 并居中 aspect-fit（GeometryReader 默认 topLeading 会把内容顶到左上/偏右裁切）
                Group {
                    if let livePhoto {
                        LivePhotoViewRepresentable(livePhoto: livePhoto)
                    } else if let still = fallbackStill {
                        FallbackLivePhotoView(
                            still: still,
                            videoURL: fallbackVideoURL,
                            isPlaying: $isPlayingFallback
                        )
                    } else if loadFailed {
                        VStack(spacing: AppTheme.Spacing.lg) {
                            Image(systemName: "livephoto.slash")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.5))
                            Text("实况照片加载失败")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    } else {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                if livePhoto != nil || fallbackStill != nil {
                    LivePhotoBadge()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .safeAreaPadding(.top, 8)
                        .padding(.leading, AppTheme.Spacing.md)
                }
            }
            .contentShape(Rectangle())
            .zoomPanGesture(scale: $scale)
            .pageSwipeGesture(isEnabled: scale <= 1.0 && !isPlayingFallback, onSwipe: onSwipe)
            .onTapGesture(count: 1, perform: onTap)
            .onLongPressGesture(minimumDuration: 0.35, pressing: { pressing in
                guard fallbackStill != nil, fallbackVideoURL != nil else { return }
                isPlayingFallback = pressing
            }, perform: {})
        }
        .task(id: file.id) {
            await loadLivePhoto()
        }
    }

    private func loadLivePhoto() async {
        livePhoto = nil
        fallbackStill = nil
        fallbackVideoURL = nil
        loadFailed = false
        isPlayingFallback = false

        guard let stillURL = contentURL(for: file),
              let videoURL = liveVideoContentURL() else {
            loadFailed = true
            return
        }

        do {
            let stillData = try await download(stillURL)
            let videoData = try await download(videoURL)

            let tmp = FileManager.default.temporaryDirectory
            let stillExt = file.extension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            let stillPath = tmp.appendingPathComponent("live_\(UUID().uuidString).\(stillExt.isEmpty ? "heic" : stillExt)")
            let videoPath = tmp.appendingPathComponent("live_\(UUID().uuidString).mov")
            try stillData.write(to: stillPath)
            try videoData.write(to: videoPath)

            if let photo = try? await requestLivePhoto(imageURL: stillPath, videoURL: videoPath) {
                try? FileManager.default.removeItem(at: stillPath)
                try? FileManager.default.removeItem(at: videoPath)
                await MainActor.run { livePhoto = photo }
                return
            }

            // 回退：UIImage 解码静帧（真机 HEIC Orientation 由 ImageIO 处理）+ 配对视频
            let stillImage = UIImage(data: stillData)
            try? FileManager.default.removeItem(at: stillPath)
            await MainActor.run {
                fallbackStill = stillImage
                fallbackVideoURL = videoPath
                if stillImage == nil { loadFailed = true }
            }
        } catch {
            await MainActor.run { loadFailed = true }
        }
    }

    private func liveVideoContentURL() -> URL? {
        if let uuid = file.liveVideoUuid {
            return apiService.preview.getContentURL(
                uuid: uuid,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        }
        if let path = file.liveVideoPath, !path.isEmpty {
            return apiService.preview.getContentURL(
                for: path,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        }
        return nil
    }

    private func contentURL(for file: FileInfo) -> URL? {
        if let uuid = file.uuid {
            return apiService.preview.getContentURL(
                uuid: uuid,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        }
        return apiService.preview.getContentURL(
            for: file.path,
            baseURL: apiService.baseURL,
            apiKey: apiService.apiKey
        )
    }

    private func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func requestLivePhoto(imageURL: URL, videoURL: URL) async throws -> PHLivePhoto {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<PHLivePhoto, Error>) in
            final class Once: @unchecked Sendable {
                var done = false
                let lock = NSLock()
                func take() -> Bool {
                    lock.lock(); defer { lock.unlock() }
                    if done { return false }
                    done = true
                    return true
                }
            }
            let once = Once()
            PHLivePhoto.request(
                withResourceFileURLs: [imageURL, videoURL],
                placeholderImage: nil,
                targetSize: CGSize(width: 4096, height: 4096),
                contentMode: .aspectFit
            ) { livePhoto, info in
                let infoDict = info ?? [:]
                let isDegraded = (infoDict[PHLivePhotoInfoIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                guard once.take() else { return }
                if let livePhoto {
                    cont.resume(returning: livePhoto)
                } else if let err = infoDict[PHLivePhotoInfoErrorKey] as? Error {
                    cont.resume(throwing: err)
                } else {
                    cont.resume(throwing: NSError(
                        domain: "LivePhoto",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "无法合成实况照片"]
                    ))
                }
            }
        }
    }
}

// MARK: - LIVE 标记（系统相册：左上、安全区下、Liquid Glass）

private struct LivePhotoBadge: View {
    var body: some View {
        Label {
            Text("LIVE")
                .font(.caption.weight(.semibold))
        } icon: {
            Image(systemName: "livephoto")
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassBackground(in: Capsule())
        .accessibilityIdentifier("livePhotoBadge")
    }
}

/// UIKit：PHLivePhotoView 常忽略 contentMode 而填满裁切；按 livePhoto.size 算 aspect-fit 框再居中。
struct LivePhotoViewRepresentable: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> LivePhotoAspectFitContainer {
        let container = LivePhotoAspectFitContainer()
        container.backgroundColor = .clear
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .clear
        view.livePhoto = livePhoto
        view.isMuted = false
        container.liveView = view
        container.addSubview(view)
        context.coordinator.container = container
        return container
    }

    func updateUIView(_ uiView: LivePhotoAspectFitContainer, context: Context) {
        uiView.liveView?.livePhoto = livePhoto
        uiView.liveView?.contentMode = .scaleAspectFit
        uiView.setNeedsLayout()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var container: LivePhotoAspectFitContainer?
    }
}

final class LivePhotoAspectFitContainer: UIView {
    var liveView: PHLivePhotoView?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let liveView else { return }
        let photoSize = liveView.livePhoto?.size ?? .zero
        guard photoSize.width > 0, photoSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            liveView.frame = bounds
            return
        }
        let scale = min(bounds.width / photoSize.width, bounds.height / photoSize.height)
        let fitted = CGSize(width: photoSize.width * scale, height: photoSize.height * scale)
        liveView.frame = CGRect(
            x: (bounds.width - fitted.width) / 2,
            y: (bounds.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}

/// 回退：静帧 aspect-fit 居中 + AVPlayer
private struct FallbackLivePhotoView: View {
    let still: UIImage
    let videoURL: URL?
    @Binding var isPlaying: Bool

    var body: some View {
        ZStack {
            Image(uiImage: still)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isPlaying ? 0 : 1)

            if let videoURL, isPlaying {
                FallbackVideoPlayer(url: videoURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct FallbackVideoPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        let player = AVPlayer(url: url)
        vc.player = player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspect
        player.isMuted = false
        player.play()
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if (vc.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            let player = AVPlayer(url: url)
            vc.player = player
            player.play()
        }
    }

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: ()) {
        vc.player?.pause()
        vc.player = nil
    }
}
