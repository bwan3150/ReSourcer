//
//  PlaylistAdvance.swift
//  ReSourcer
//
//  播放列表前进：自动连播时跳过非音视频（图片 / PDF / other），避免后台播放停在静图上。
//

import Foundation

enum PlaylistAdvance {

    /// 是否为可连续播放的音视频
    static func isPlayableAV(_ file: FileInfo) -> Bool {
        file.isVideo || file.isAudio
    }

    /// 从 `fromIndex` 起按 `direction` 找下一个条目（可跳过非音视频与同 uuid 重复项）。
    /// - Returns: 目标下标；找不到则 nil
    static func nextIndex(
        playlist: [FileInfo],
        from fromIndex: Int,
        direction: Int,
        wrap: Bool,
        skipNonPlayable: Bool
    ) -> Int? {
        guard playlist.count > 1, playlist.indices.contains(fromIndex) else { return nil }
        let step = direction >= 0 ? 1 : -1
        let currentId = playlist[fromIndex].uuid ?? playlist[fromIndex].path

        var idx = fromIndex
        for _ in 0..<playlist.count {
            idx += step
            if idx < 0 || idx >= playlist.count {
                guard wrap else { return nil }
                idx = step > 0 ? 0 : playlist.count - 1
            }
            let candidate = playlist[idx]
            let candidateId = candidate.uuid ?? candidate.path
            if candidateId == currentId { continue }
            if skipNonPlayable && !isPlayableAV(candidate) { continue }
            return idx
        }
        return nil
    }
}
