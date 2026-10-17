//
//  LivePhotoPreviewContent.swift
//  ReSourcer
//
//  实况照片预览：PHLivePhotoView 按住播放配对 MOV；原生 LIVE 标记（SF Symbol，无 emoji）。
//

import SwiftUI
import PhotosUI
import Photos
import UIKit

/// 实况照片查看：下载静帧 + 配对视频 → PHLivePhoto → 按住播放
struct LivePhotoPreviewContent: View {

    let file: FileInfo
    let apiService: APIService
    let onTap: () -> Void
    let onSwipe: (Int) -> Bool

    @State private var livePhoto: PHLivePhoto?
    @State private var loadFailed = false
    @State private var scale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let livePhoto {
                    LivePhotoViewRepresentable(livePhoto: livePhoto)
                        .frame(width: geometry.size.width, height: geometry.size.height)
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
            .contentShape(Rectangle())
            .zoomPanGesture(scale: $scale)
            .pageSwipeGesture(isEnabled: scale <= 1.0, onSwipe: onSwipe)
            .onTapGesture(count: 1, perform: onTap)
        }
        .task(id: file.id) {
            await loadLivePhoto()
        }
    }

    private func loadLivePhoto() async {
        livePhoto = nil
        loadFailed = false

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
            defer {
                try? FileManager.default.removeItem(at: stillPath)
                try? FileManager.default.removeItem(at: videoPath)
            }

            let photo = try await requestLivePhoto(imageURL: stillPath, videoURL: videoPath)
            await MainActor.run {
                livePhoto = photo
            }
        } catch {
            await MainActor.run {
                loadFailed = true
            }
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
                let isDegraded = (info?[PHLivePhotoInfoIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                guard once.take() else { return }
                if let livePhoto {
                    cont.resume(returning: livePhoto)
                } else if let err = info?[PHLivePhotoInfoErrorKey] as? Error {
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
