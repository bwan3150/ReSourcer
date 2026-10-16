//
//  NowPlayingController.swift
//  ReSourcer
//
//  锁屏 / 控制中心：Now Playing 信息 + 远程控制命令
//  上一个 / 下一个由预览页注册，遵循当前播放模式（随机 / 列表循环 / 单曲 / 同类型）
//

import Foundation
import MediaPlayer
import UIKit
import AVFoundation

extension Notification.Name {
    static let nowPlayingRemotePlay = Notification.Name("ReSourcer.nowPlayingRemotePlay")
    static let nowPlayingRemotePause = Notification.Name("ReSourcer.nowPlayingRemotePause")
    static let nowPlayingRemoteToggle = Notification.Name("ReSourcer.nowPlayingRemoteToggle")
    static let nowPlayingRemoteNext = Notification.Name("ReSourcer.nowPlayingRemoteNext")
    static let nowPlayingRemotePrevious = Notification.Name("ReSourcer.nowPlayingRemotePrevious")
    static let nowPlayingRemoteSeek = Notification.Name("ReSourcer.nowPlayingRemoteSeek")
}

/// 管理 MPNowPlayingInfoCenter 与 MPRemoteCommandCenter。
/// 远程命令通过 NotificationCenter 送达预览页（SwiftUI @State 可在 onReceive 中安全写入）。
@MainActor
final class NowPlayingController {

    static let shared = NowPlayingController()

    /// seek 目标秒数放在 notification.userInfo["position"]
    static let seekPositionKey = "position"

    /// 是否允许上一个 / 下一个（与预览页 canGoPrev / canGoNext 对齐）
    var canGoPrevious: Bool = false {
        didSet { updateSkipCommandEnabled() }
    }
    var canGoNext: Bool = false {
        didSet { updateSkipCommandEnabled() }
    }

    /// 当前预览页注册的 seek 处理（AVPlayer 在子视图内）
    var onSeek: ((TimeInterval) -> Void)?

    private var commandsConfigured = false
    private var isActive = false

    private init() {}

    // MARK: - Audio session

    /// 配置 `.playback` 会话，允许退后台继续出声
    func activatePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // 会话失败不阻断播放；锁屏控制可能不可用
            print("[NowPlaying] AVAudioSession 激活失败: \(error.localizedDescription)")
        }
        configureRemoteCommandsIfNeeded()
        // beginReceivingRemoteControlEvents 在纯 SwiftUI 场景非必需；异常时忽略，避免阻断播放
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    // MARK: - Now Playing 更新

    /// 设置 / 刷新锁屏与控制中心元数据（可拖动进度）
    func update(
        title: String,
        artist: String? = nil,
        duration: TimeInterval,
        elapsed: TimeInterval,
        isPlaying: Bool,
        artworkImage: UIImage? = nil
    ) {
        isActive = true
        configureRemoteCommandsIfNeeded()

        let safeElapsed = Self.sanitizedTime(elapsed)
        let safeDuration = Self.sanitizedTime(duration)

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: safeElapsed,
            MPMediaItemPropertyPlaybackDuration: safeDuration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if let artist, !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let artwork = Self.makeArtwork(from: artworkImage) {
            info[MPMediaItemPropertyArtwork] = artwork
        } else if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = existing
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateSkipCommandEnabled()
    }

    /// 仅刷新进度与播放速率（时间观察器高频调用）
    func updatePlaybackProgress(elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        guard isActive else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Self.sanitizedTime(elapsed)
        let safeDuration = Self.sanitizedTime(duration)
        if safeDuration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = safeDuration
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// 预览关闭 / 切到非媒体时清空
    func clear() {
        isActive = false
        canGoPrevious = false
        canGoNext = false
        onSeek = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Sanitizers（NaN / 零尺寸封面会导致系统 Now Playing 崩溃）

    /// CMTime.seconds 在未就绪时常为 NaN；写入 MPNowPlayingInfo 会直接崩
    static func sanitizedTime(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }

    /// boundsSize 为 .zero 时 MPMediaItemArtwork 会断言崩溃
    static func makeArtwork(from image: UIImage?) -> MPMediaItemArtwork? {
        guard let image else { return nil }
        let size = image.size
        guard size.width >= 1, size.height >= 1, size.width.isFinite, size.height.isFinite else {
            return nil
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }

    // MARK: - Remote commands

    private func configureRemoteCommandsIfNeeded() {
        guard !commandsConfigured else { return }
        commandsConfigured = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { _ in
            NotificationCenter.default.post(name: .nowPlayingRemotePlay, object: nil)
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { _ in
            NotificationCenter.default.post(name: .nowPlayingRemotePause, object: nil)
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { _ in
            NotificationCenter.default.post(name: .nowPlayingRemoteToggle, object: nil)
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard self?.canGoNext == true else { return }
                NotificationCenter.default.post(name: .nowPlayingRemoteNext, object: nil)
            }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard self?.canGoPrevious == true else { return }
                NotificationCenter.default.post(name: .nowPlayingRemotePrevious, object: nil)
            }
            return .success
        }

        // 可拖动 seek
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = Self.sanitizedTime(positionEvent.positionTime)
            Task { @MainActor in
                if let onSeek = self?.onSeek {
                    onSeek(position)
                } else {
                    NotificationCenter.default.post(
                        name: .nowPlayingRemoteSeek,
                        object: nil,
                        userInfo: [NowPlayingController.seekPositionKey: position]
                    )
                }
            }
            return .success
        }

        // 禁用不支持的命令，避免系统露出空控件
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
    }

    private func updateSkipCommandEnabled() {
        let center = MPRemoteCommandCenter.shared()
        center.previousTrackCommand.isEnabled = canGoPrevious
        center.nextTrackCommand.isEnabled = canGoNext
    }
}
