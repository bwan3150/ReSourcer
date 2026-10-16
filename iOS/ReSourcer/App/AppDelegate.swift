//
//  AppDelegate.swift
//  ReSourcer
//
//  UIKit 生命周期钩子：后台 URLSession 事件 + 音频会话预热
//

import UIKit
import AVFoundation

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 预配置播放会话（实际激活在开始播放时；此处仅设 category，避免抢占）
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        } catch {
            print("[AppDelegate] AVAudioSession category 设置失败: \(error.localizedDescription)")
        }
        // 触达 background session，尽早与系统重连未完成的上传任务
        _ = BackgroundUploadSession.shared
        _ = BackgroundUploadManager.shared
        BackgroundUploadManager.shared.resumePendingFinalizations()
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == BackgroundUploadSession.sessionIdentifier {
            BackgroundUploadSession.shared.handleEventsForBackgroundURLSession(
                completionHandler: completionHandler
            )
            return
        }

        if identifier == AppGroup.backgroundUploadSessionId {
            BackgroundUploadManager.shared.setBackgroundCompletionHandler(
                completionHandler,
                for: identifier
            )
            _ = BackgroundUploadManager.shared
            BackgroundUploadManager.shared.resumePendingFinalizations()
            return
        }

        completionHandler()
    }
}
