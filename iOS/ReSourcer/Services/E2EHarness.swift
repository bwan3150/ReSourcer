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
        // OK|title|duration|elapsed|rate|artwork|bgAdvanced
        nowPlayingProbeText = String(
            format: "OK|%@|%.3f|%.3f|%.2f|%d|%@",
            snap.title.replacingOccurrences(of: "|", with: "_"),
            snap.duration,
            snap.elapsed,
            snap.rate,
            snap.hasArtwork ? 1 : 0,
            bg
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

    /// Phase 1：init + 仅第 0 片 → 持久化 job → READY_TO_KILL
    func startKillUploadIfNeeded(apiService: APIService) {
        let env = ProcessInfo.processInfo.environment
        guard env["E2E_KILL_UPLOAD"] == "1" else { return }
        uploadProbeText = "STARTING"
        Task {
            do {
                _ = try await apiService.upload.updateUploadPolicy(chunkSizeMb: 1)
                let chunkSize = 1 * 1024 * 1024
                let totalBytes = chunkSize * 2 + 200_000
                var data = Data(count: totalBytes)
                for i in 0..<totalBytes {
                    data[i] = UInt8(i % 251)
                }
                let fileName = "e2e-kill-resume-\(Int(Date().timeIntervalSince1970)).bin"
                let sources = try await apiService.config.getSourceFolders()
                let result = try await apiService.upload.preparePartialChunkJobForE2E(
                    fileName: fileName,
                    data: data,
                    targetFolder: sources.current,
                    chunkSize: chunkSize,
                    uploadFirstChunkOnly: true
                )
                await MainActor.run {
                    self.uploadProbeText =
                        "READY_TO_KILL|\(result.uploadId)|\(result.fileName)|\(result.jobId)"
                }
            } catch {
                await MainActor.run {
                    self.uploadProbeText = "ERROR:\(error.localizedDescription)"
                }
            }
        }
    }

    /// Phase 2：冷启动 resume + 校验目标目录文件完整
    func checkUploadResumeIfNeeded(apiService: APIService) {
        let env = ProcessInfo.processInfo.environment
        guard env["E2E_UPLOAD_RESUME_CHECK"] == "1" else { return }
        uploadProbeText = "RESUMING"
        Task {
            let finished = await apiService.upload.resumePendingChunkJobs()
            try? await Task.sleep(nanoseconds: 800_000_000)
            let jobsLeft = ChunkUploadJobStore.loadAll()
            if jobsLeft.isEmpty, !finished.isEmpty {
                do {
                    let sources = try await apiService.config.getSourceFolders()
                    let browse = try await apiService.browser.browse(path: sources.current)
                    let hit = browse.items.first {
                        $0.name.hasPrefix("e2e-kill-resume-") && !$0.isDirectory
                    }
                    if let hit {
                        // DirectoryItem 无 size；用本地磁盘路径核对（E2E 服务器与模拟器同机）
                        let attrs = try? FileManager.default.attributesOfItem(atPath: hit.path)
                        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? -1
                        let intact = size >= 2 * 1024 * 1024
                        await MainActor.run {
                            self.uploadProbeText = intact
                                ? "RESUME_OK|\(hit.name)|\(size)"
                                : "RESUME_BAD_SIZE|\(hit.name)|\(size)"
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
