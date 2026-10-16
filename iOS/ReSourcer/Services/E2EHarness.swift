//
//  E2EHarness.swift
//  ReSourcer
//
//  UITest / 真机后端探针：Now Playing 快照、遥控命令、杀进程上传续传。
//  仅在 launchEnvironment 打开时生效，不影响正常用户路径。
//

import Foundation
import MediaPlayer
import UIKit
import SwiftUI

/// E2E 探针状态（写到无障碍 value，供 XCUITest 读取）
@MainActor
final class E2EHarness: ObservableObject {
    static let shared = E2EHarness()

    @Published var nowPlayingProbeText: String = ""
    @Published var uploadProbeText: String = ""
    /// playlistCount|index|canNext|canPrev（由 FilePreviewView 写入）
    var playlistMeta: String = "0|0|0|0"

    private var nowPlayingTimer: Timer?
    private var backgroundMarkElapsed: TimeInterval?
    private var didAdvanceWhileBackground = false
    private var observersInstalled = false

    private init() {}

    // MARK: - Now Playing probe

    func startNowPlayingProbeIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        guard env["E2E_NOWPLAYING_PROBE"] == "1" else { return }
        nowPlayingTimer?.invalidate()
        nowPlayingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNowPlayingProbe()
            }
        }
        if let timer = nowPlayingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        refreshNowPlayingProbe()
        installLifecycleObserversIfNeeded()
    }

    private func installLifecycleObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.backgroundMarkElapsed = Self.readNowPlaying().elapsed
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let mark = self.backgroundMarkElapsed else { return }
                let now = Self.readNowPlaying()
                if now.rate > 0.5, now.elapsed > mark + 0.8 {
                    self.didAdvanceWhileBackground = true
                }
                self.refreshNowPlayingProbe()
            }
        }
    }

    private func refreshNowPlayingProbe() {
        let snap = Self.readNowPlaying()
        let bg = didAdvanceWhileBackground ? "1" : "0"
        // OK|title|duration|elapsed|rate|artwork|bgAdvanced|loop|shuffle|plMeta
        let loop = LocalStorageService.shared.getListLoopEnabled() ? "1" : "0"
        let shuffle = LocalStorageService.shared.getShuffleEnabled() ? "1" : "0"
        nowPlayingProbeText = String(
            format: "OK|%@|%.3f|%.3f|%.2f|%d|%@|%@|%@|%@",
            snap.title.replacingOccurrences(of: "|", with: "_"),
            snap.duration,
            snap.elapsed,
            snap.rate,
            snap.hasArtwork ? 1 : 0,
            bg,
            loop,
            shuffle,
            playlistMeta
        )
    }

    struct NowPlayingSnap {
        var title: String
        var duration: TimeInterval
        var elapsed: TimeInterval
        var rate: Double
        var hasArtwork: Bool
    }

    nonisolated static func readNowPlaying() -> NowPlayingSnap {
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        let title = (info[MPMediaItemPropertyTitle] as? String) ?? ""
        let duration = NowPlayingController.sanitizedTime(
            (info[MPMediaItemPropertyPlaybackDuration] as? NSNumber)?.doubleValue ?? 0
        )
        let elapsed = NowPlayingController.sanitizedTime(
            (info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? 0
        )
        let rate = (info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue ?? 0
        let hasArtwork = info[MPMediaItemPropertyArtwork] != nil
        return NowPlayingSnap(
            title: title,
            duration: duration,
            elapsed: elapsed,
            rate: rate,
            hasArtwork: hasArtwork
        )
    }

    /// UITest 点按隐藏按钮 / 深链触发与锁屏相同的远端通知
    static func fireRemoteCommand(_ cmd: String, seekSeconds: TimeInterval = 1.5) {
        switch cmd {
        case "play":
            NotificationCenter.default.post(name: .nowPlayingRemotePlay, object: nil)
        case "pause":
            NotificationCenter.default.post(name: .nowPlayingRemotePause, object: nil)
        case "toggle":
            NotificationCenter.default.post(name: .nowPlayingRemoteToggle, object: nil)
        case "next":
            NotificationCenter.default.post(name: .nowPlayingRemoteNext, object: nil)
        case "previous":
            NotificationCenter.default.post(name: .nowPlayingRemotePrevious, object: nil)
        case "seek":
            NotificationCenter.default.post(
                name: .nowPlayingRemoteSeek,
                object: nil,
                userInfo: [NowPlayingController.seekPositionKey: NowPlayingController.sanitizedTime(seekSeconds)]
            )
        default:
            break
        }
    }

    /// 深链：`resourcer://e2e/np?cmd=play|pause|toggle|next|previous|seek&t=1.5`
    static func handleNowPlayingDeepLink(_ url: URL) -> Bool {
        guard url.scheme == AppGroup.urlScheme, url.host == "e2e" else { return false }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty, path != "np" { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let cmd = items.first(where: { $0.name == "cmd" })?.value ?? ""
        guard !cmd.isEmpty else { return false }
        let seek = Double(items.first(where: { $0.name == "t" })?.value ?? "1.5") ?? 1.5
        fireRemoteCommand(cmd, seekSeconds: seek)
        return true
    }

    // MARK: - Kill / resume upload

    private enum KillUploadKeys {
        static let expectedBytes = "e2e_kill_expected_bytes"
        static let fileName = "e2e_kill_file_name"
        static let chunksBeforeKill = "e2e_kill_chunks_before"
    }

    /// Phase 1：大文件分片，只传前 N 片 → 持久化 job → READY_TO_KILL
    /// 默认 ~12MB / 1MB 分片，先传 2 片再杀（模拟中途被杀）。
    func startKillUploadIfNeeded(apiService: APIService) {
        let env = ProcessInfo.processInfo.environment
        guard env["E2E_KILL_UPLOAD"] == "1" else { return }
        uploadProbeText = "STARTING"
        let mb = Int(env["E2E_KILL_UPLOAD_MB"] ?? "12") ?? 12
        let chunksBeforeKill = max(1, Int(env["E2E_KILL_CHUNKS_BEFORE"] ?? "2") ?? 2)
        Task {
            do {
                _ = try await apiService.upload.updateUploadPolicy(chunkSizeMb: 1)
                let chunkSize = 1 * 1024 * 1024
                let totalBytes = max(chunkSize * (chunksBeforeKill + 2), mb * 1024 * 1024)
                var data = Data(count: totalBytes)
                for i in stride(from: 0, to: totalBytes, by: 4096) {
                    data[i] = UInt8((i / 4096) % 251)
                }
                let fileName = "e2e-kill-resume-\(Int(Date().timeIntervalSince1970)).bin"
                let sources = try await apiService.config.getSourceFolders()
                let result = try await apiService.upload.preparePartialChunkJobForE2E(
                    fileName: fileName,
                    data: data,
                    targetFolder: sources.current,
                    chunkSize: chunkSize,
                    uploadFirstChunkCount: chunksBeforeKill
                )
                AppGroup.defaults.set(totalBytes, forKey: KillUploadKeys.expectedBytes)
                AppGroup.defaults.set(fileName, forKey: KillUploadKeys.fileName)
                AppGroup.defaults.set(chunksBeforeKill, forKey: KillUploadKeys.chunksBeforeKill)
                await MainActor.run {
                    self.uploadProbeText =
                        "READY_TO_KILL|\(result.uploadId)|\(result.fileName)|\(result.jobId)|\(totalBytes)|\(chunksBeforeKill)/\(result.totalChunks)"
                }
            } catch {
                await MainActor.run {
                    self.uploadProbeText = "ERROR:\(error.localizedDescription)"
                }
            }
        }
    }

    /// Phase 2：冷启动 resume + 校验目标文件字节数与文件名
    func checkUploadResumeIfNeeded(apiService: APIService) {
        let env = ProcessInfo.processInfo.environment
        guard env["E2E_UPLOAD_RESUME_CHECK"] == "1" else { return }
        uploadProbeText = "RESUMING"
        let expectedBytes = AppGroup.defaults.integer(forKey: KillUploadKeys.expectedBytes)
        let expectedName = AppGroup.defaults.string(forKey: KillUploadKeys.fileName) ?? ""
        Task {
            let finished = await apiService.upload.resumePendingChunkJobs()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let jobsLeft = ChunkUploadJobStore.loadAll()
            if jobsLeft.isEmpty, !finished.isEmpty {
                do {
                    let sources = try await apiService.config.getSourceFolders()
                    let browse = try await apiService.browser.browse(path: sources.current)
                    let hit = browse.items.first { item in
                        guard !item.isDirectory else { return false }
                        if !expectedName.isEmpty { return item.name == expectedName }
                        return item.name.hasPrefix("e2e-kill-resume-")
                    }
                    if let hit {
                        let attrs = try? FileManager.default.attributesOfItem(atPath: hit.path)
                        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? -1
                        let need = expectedBytes > 0 ? Int64(expectedBytes) : (12 * 1024 * 1024)
                        let intact = size == need
                        await MainActor.run {
                            self.uploadProbeText = intact
                                ? "RESUME_OK|\(hit.name)|\(size)"
                                : "RESUME_BAD_SIZE|\(hit.name)|\(size)|expected:\(need)"
                        }
                        return
                    }
                    await MainActor.run {
                        self.uploadProbeText = "RESUME_OK_NO_FILE|\(finished.joined(separator: ","))"
                    }
                } catch {
                    await MainActor.run {
                        self.uploadProbeText = "RESUME_LIST_ERROR:\(error.localizedDescription)"
                    }
                }
            } else if !jobsLeft.isEmpty {
                await MainActor.run {
                    self.uploadProbeText = "RESUME_PENDING|\(jobsLeft.count)"
                }
            } else {
                await MainActor.run {
                    self.uploadProbeText = "RESUME_NOTHING"
                }
            }
        }
    }
}

// MARK: - Overlay for UITests

struct E2EProbeOverlay: View {
    @ObservedObject var harness: E2EHarness = .shared
    let showNowPlaying: Bool
    let showUpload: Bool
    let showRemoteButtons: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showNowPlaying, !harness.nowPlayingProbeText.isEmpty {
                Text(harness.nowPlayingProbeText)
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("e2eNowPlayingProbe")
                    .accessibilityValue(harness.nowPlayingProbeText)
            }
            if showUpload, !harness.uploadProbeText.isEmpty {
                Text(harness.uploadProbeText)
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityIdentifier("e2eUploadProbe")
                    .accessibilityValue(harness.uploadProbeText)
            }
            if showRemoteButtons {
                HStack(spacing: 4) {
                    remoteButton("play")
                    remoteButton("pause")
                    remoteButton("toggle")
                    remoteButton("next")
                    remoteButton("previous")
                    remoteButton("seek")
                }
            }
        }
        .allowsHitTesting(showRemoteButtons)
        .padding(4)
    }

    private func remoteButton(_ cmd: String) -> some View {
        Button(cmd) {
            E2EHarness.fireRemoteCommand(cmd)
        }
        .font(.system(size: 8))
        .opacity(0.02)
        .accessibilityIdentifier("e2eRemote-\(cmd)")
    }
}
