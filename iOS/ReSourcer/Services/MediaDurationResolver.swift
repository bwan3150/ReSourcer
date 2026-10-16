//
//  MediaDurationResolver.swift
//  ReSourcer
//
//  解析 AVPlayer / 文件元数据中的真实时长，避免 Now Playing 卡在占位 1 秒。
//

import Foundation
import AVFoundation

enum MediaDurationResolver {

    /// 优先 playerItem 时长 → seekable 末端 → 索引元数据 → 已有值
    static func resolve(
        playerItem: AVPlayerItem?,
        fileDuration: Double?,
        current: Double = 0
    ) -> TimeInterval {
        if let item = playerItem {
            let fromItem = NowPlayingController.sanitizedTime(item.duration.seconds)
            if fromItem > 0 { return fromItem }

            if let last = item.seekableTimeRanges.last {
                let range = last.timeRangeValue
                let end = NowPlayingController.sanitizedTime(
                    CMTimeGetSeconds(range.start + range.duration)
                )
                if end > 0 { return end }
            }
        }

        if let fileDuration {
            let meta = NowPlayingController.sanitizedTime(fileDuration)
            if meta > 0 { return meta }
        }

        let kept = NowPlayingController.sanitizedTime(current)
        return kept > 0 ? kept : 0
    }

    /// 异步从 AVURLAsset 加载时长（流媒体 item.duration 常为 indefinite 时的兜底）
    static func loadAssetDuration(url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let dur = try await asset.load(.duration)
            return NowPlayingController.sanitizedTime(dur.seconds)
        } catch {
            return 0
        }
    }
}
