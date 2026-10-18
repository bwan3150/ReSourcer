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
                // 黑底 + overlay 居中 aspect-fit（与 ImagePreviewContent 同一套路）
                Color.black
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay {
                        Group {
                            if let livePhoto {
                                let photo = livePhoto.size
                                let fitted: CGSize = {
                                    guard photo.width > 1, photo.height > 1 else {
                                        return geometry.size
                                    }
                                    let scale = min(
                                        geometry.size.width / photo.width,
                                        geometry.size.height / photo.height
                                    )
                                    return CGSize(
                                        width: photo.width * scale,
                                        height: photo.height * scale
                                    )
                                }()
                                LivePhotoViewRepresentable(livePhoto: livePhoto)
                                    .frame(width: fitted.width, height: fitted.height)
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
                    }

                if livePhoto != nil || fallbackStill != nil {
                    // 父级 FilePreviewView 对媒体层 ignoresSafeArea，safeAreaPadding 会变成 0；
                    // 显式用窗口安全区把 LIVE 放到状态栏下方（对齐系统相册）。
                    // 状态栏 + 顶栏返回按钮行之下（约 44pt），避免叠时钟/返回键
                    LivePhotoBadge()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, Self.statusBarInset + 52)
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

    /// 媒体层常 ignoresSafeArea，不能依赖 GeometryReader.safeAreaInsets
    private static var statusBarInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let inset = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top
        return inset ?? scenes.first?.windows.first?.safeAreaInsets.top ?? 54
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

/// UIKit：外层由 SwiftUI `.aspectRatio(..., .fit)` 约束；此处铺满该外框。
struct LivePhotoViewRepresentable: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.livePhoto = livePhoto
        view.isMuted = false
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = livePhoto
        uiView.contentMode = .scaleAspectFit
        uiView.clipsToBounds = true
    }
}

/// 回退：静帧 aspect-fit 居中 + AVPlayer
private struct FallbackLivePhotoView: View {
    let still: UIImage
    let videoURL: URL?
    @Binding var isPlaying: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: still)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(isPlaying ? 0 : 1)

                if let videoURL, isPlaying {
                    FallbackVideoPlayer(url: videoURL)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
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
