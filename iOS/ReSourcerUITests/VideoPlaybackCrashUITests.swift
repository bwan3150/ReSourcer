//
//  VideoPlaybackCrashUITests.swift
//  ReSourcerUITests
//
//  真实后端：打开真实视频，确认不会因 Now Playing / 音频会话立即崩溃。
//
//  运行：
//    E2E_SERVER_URL=http://127.0.0.1:1234 E2E_API_KEY=… bash iOS/scripts/run-ui-tests.sh
//

import XCTest

final class VideoPlaybackCrashUITests: XCTestCase {

    var app: XCUIApplication!

    /// 与 E2E 源目录中 `e2e-sample.mp4` 索引 UUID 对齐（fixture 固定）
    private let sampleVideoUUID = "ed062d4b-c01a-486d-b673-9b6ae1a288f3"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY to run real-backend video playback UI E2E"
        )

        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launch()
    }

    /// 打开真实视频 → 停留数秒 → App 仍在前台运行（不因 Now Playing 崩溃）
    func testOpenRealVideoDoesNotCrash() throws {
        let videoItem = app.descendants(matching: .any)["fileGridItem-\(sampleVideoUUID)"]
        guard videoItem.waitForExistence(timeout: 20) else {
            throw XCTSkip(
                "Missing fileGridItem-\(sampleVideoUUID) — seed e2e-sample.mp4 and reindex on E2E server"
            )
        }

        videoItem.tap()

        // 预览 chrome（点一下屏幕可唤醒自动隐藏的控件）
        let modeBtn = app.descendants(matching: .any)["playbackModeButton"]
        let playPause = app.descendants(matching: .any)["previewPlayPauseButton"]
        if !modeBtn.waitForExistence(timeout: 3) && !playPause.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let chromeVisible = modeBtn.waitForExistence(timeout: 12) || playPause.waitForExistence(timeout: 2)
        XCTAssertTrue(chromeVisible, "preview should open for video without crashing")

        // 给 AVPlayer + Now Playing（含封面回调）足够时间；崩溃多发于 artwork handler
        RunLoop.current.run(until: Date().addingTimeInterval(5))

        XCTAssertEqual(app.state, .runningForeground, "app must stay alive while playing video")
        // 再点一次确认进程仍响应（未因 SIGTRAP 被杀）
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertEqual(app.state, .runningForeground, "app must still respond after Now Playing artwork path")
    }
}
