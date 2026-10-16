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

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, elapsed),
            MPMediaItemPropertyPlaybackDuration: max(0, duration),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if let artist, !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let artworkImage {
            let artwork = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
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
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, elapsed)
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
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
            let position = positionEvent.positionTime
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
