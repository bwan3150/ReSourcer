//
//  LivePhotoPreviewContent.swift
//  ReSourcer
//
//  实况照片预览：优先 PHLivePhotoView；合成失败时回退静帧（大缩略图，已按 Orientation 转正）+ 按住播配对 MOV。
//  原生 LIVE 标记（SF Symbol，无 emoji）。
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
                if let livePhoto {
                    LivePhotoViewRepresentable(livePhoto: livePhoto)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if let still = fallbackStill {
                    FallbackLivePhotoView(
                        still: still,
                        videoURL: fallbackVideoURL,
                        isPlaying: $isPlayingFallback,
                        size: geometry.size
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

                // 原生 LIVE 标记：图标 only，禁止 emoji
                if livePhoto != nil || fallbackStill != nil {
                    VStack {
                        HStack {
                            Spacer()
                            Label {
                                Text("LIVE")
                                    .font(.caption.weight(.semibold))
                            } icon: {
                                Image(systemName: "livephoto")
                            }
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.45), in: Capsule())
                            .accessibilityIdentifier("livePhotoBadge")
                            .padding(.trailing, AppTheme.Spacing.md)
                            .padding(.top, AppTheme.Spacing.md)
                        }
                        Spacer()
                    }
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

            // 尝试系统实况合成（真机相册导出的 HEIC+MOV 带 Content Identifier）
            if let photo = try? await requestLivePhoto(imageURL: stillPath, videoURL: videoPath) {
                try? FileManager.default.removeItem(at: stillPath)
                // 保留 videoPath 无用；PHLivePhoto 已内嵌
                try? FileManager.default.removeItem(at: videoPath)
                await MainActor.run { livePhoto = photo }
                return
            }

            // 回退：服务端大缩略图（已按 Orientation 转正）+ 配对视频按住播放
            let orientedStill = await loadOrientedStillImage()
                ?? UIImage(data: stillData)
            try? FileManager.default.removeItem(at: stillPath)
            await MainActor.run {
                fallbackStill = orientedStill
                fallbackVideoURL = videoPath
                if orientedStill == nil {
                    loadFailed = true
                }
            }
        } catch {
            await MainActor.run {
                loadFailed = true
            }
        }
    }

    /// 大图预览用服务端 tv 缩略图（HEIC Orientation 常不被 ImageIO 识别；服务端已用 exiftool 转正）
    private func loadOrientedStillImage() async -> UIImage? {
        let url: URL?
        if let uuid = file.uuid {
            url = apiService.preview.getThumbnailURL(
                uuid: uuid,
                size: 1600,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        } else {
            url = apiService.preview.getThumbnailURL(
                for: file.path,
                size: 1600,
                baseURL: apiService.baseURL,
                apiKey: apiService.apiKey
            )
        }
        guard let url else { return nil }
        do {
            let data = try await download(url)
            return UIImage(data: data)
        } catch {
            return nil
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

/// UIKit 包装：系统 PHLivePhotoView（按住播放 / 松手停）
struct LivePhotoViewRepresentable: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.livePhoto = livePhoto
        view.isMuted = false
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        if uiView.livePhoto !== livePhoto {
            uiView.livePhoto = livePhoto
        }
    }
}

/// 无 Content Identifier 时的回退：静帧 + AVPlayer 按住播放
private struct FallbackLivePhotoView: View {
    let still: UIImage
    let videoURL: URL?
    @Binding var isPlaying: Bool
    let size: CGSize

    var body: some View {
        ZStack {
            Image(uiImage: still)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
                .opacity(isPlaying ? 0 : 1)

            if let videoURL, isPlaying {
                FallbackVideoPlayer(url: videoURL)
                    .frame(width: size.width, height: size.height)
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
        if vc.player?.currentItem?.asset !== AVURLAsset(url: url) {
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
