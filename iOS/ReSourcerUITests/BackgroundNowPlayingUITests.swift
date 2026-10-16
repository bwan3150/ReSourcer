//
//  BackgroundNowPlayingUITests.swift
//  ReSourcerUITests
//
//  真实后端：播放视频 → 退后台 → 回前台校验进度前进；深链遥控 pause/play/seek/next。
//

import XCTest

final class BackgroundNowPlayingUITests: XCTestCase {

    var app: XCUIApplication!

    /// 10s 带音轨 fixture（比短 sample 更适合后台进度断言）
    private let bgVideoUUID = "8f845786-71ef-4bce-9797-6d4b6d1ced8a"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY to run background Now Playing UI E2E"
        )

        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launchEnvironment["E2E_NOWPLAYING_PROBE"] = "1"
        app.launch()
    }

    func testBackgroundPlaybackAndRemoteCommands() throws {
        let videoItem = app.descendants(matching: .any)["fileGridItem-\(bgVideoUUID)"]
        guard videoItem.waitForExistence(timeout: 20) else {
            throw XCTSkip(
                "Missing fileGridItem-\(bgVideoUUID) — seed e2e-bg-audio.mp4 and reindex"
            )
        }
        videoItem.tap()

        let playPause = app.descendants(matching: .any)["previewPlayPauseButton"]
        if !playPause.waitForExistence(timeout: 4) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(
            playPause.waitForExistence(timeout: 12),
            "preview chrome should appear for video"
        )

        let probe = app.descendants(matching: .any)["e2eNowPlayingProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 15), "Now Playing probe should appear")

        var snap = waitForProbe(containing: "e2e-bg-audio", rateAtLeast: 0.5, timeout: 20)
        XCTAssertGreaterThan(snap.duration, 2.0, "duration should be set from real video")
        let elapsedBeforeBG = snap.elapsed

        // 退后台数秒 → 回前台：进度应前进，且 bgAdvanced=1
        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(3.5))
        app.activate()

        snap = waitForProbe(matching: { $0.bgAdvanced || $0.elapsed > elapsedBeforeBG + 1.5 }, timeout: 15)
        XCTAssertTrue(
            snap.bgAdvanced || snap.elapsed > elapsedBeforeBG + 1.5,
            "playback should advance while backgrounded: \(snap.raw)"
        )
        XCTAssertEqual(app.state, .runningForeground)

        // 深链遥控（避免点按隐藏按钮误关预览 → onDisappear clear Now Playing）
        fireRemote("pause")
        snap = waitForProbe(matching: { $0.rate < 0.1 && !$0.title.isEmpty }, timeout: 10)
        XCTAssertLessThan(snap.rate, 0.1, "pause remote should stop rate: \(snap.raw)")
        XCTAssertFalse(snap.title.isEmpty, "Now Playing must survive pause: \(snap.raw)")

        fireRemote("play")
        snap = waitForProbe(matching: { $0.rate > 0.5 && !$0.title.isEmpty }, timeout: 10)
        XCTAssertGreaterThan(snap.rate, 0.5, "play remote should resume: \(snap.raw)")

        fireRemote("seek")
        snap = waitForProbe(matching: { abs($0.elapsed - 1.5) < 1.2 }, timeout: 10)
        XCTAssertEqual(snap.elapsed, 1.5, accuracy: 1.2, "seek remote: \(snap.raw)")

        let titleBefore = snap.title
        fireRemote("next")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        let afterNext = parseProbe()
        XCTAssertEqual(app.state, .runningForeground)
        if afterNext.title != titleBefore {
            fireRemote("previous")
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        }
        XCTAssertEqual(app.state, .runningForeground, "app must survive remote skip commands")
    }

    /// 通过 URL Scheme 注入与锁屏相同的远端命令（不点 UI）
    private func fireRemote(_ cmd: String) {
        let url = URL(string: "resourcer://e2e/np?cmd=\(cmd)")!
        // iOS 16.4+ / XCTest：把 URL 交给被测 App
        XCUIDevice.shared.system.open(url)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.activate()
    }

    // MARK: - Probe helpers

    private struct ProbeSnap {
        let raw: String
        let title: String
        let duration: Double
        let elapsed: Double
        let rate: Double
        let hasArtwork: Bool
        let bgAdvanced: Bool
    }

    private func parseProbe() -> ProbeSnap {
        let probe = app.descendants(matching: .any)["e2eNowPlayingProbe"]
        let raw = probe.value as? String ?? ""
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 7, parts[0] == "OK" else {
            return ProbeSnap(
                raw: raw, title: "", duration: 0, elapsed: 0, rate: 0,
                hasArtwork: false, bgAdvanced: false
            )
        }
        return ProbeSnap(
            raw: raw,
            title: parts[1],
            duration: Double(parts[2]) ?? 0,
            elapsed: Double(parts[3]) ?? 0,
            rate: Double(parts[4]) ?? 0,
            hasArtwork: parts[5] == "1",
            bgAdvanced: parts[6] == "1"
        )
    }

    private func waitForProbe(
        containing titlePart: String? = nil,
        rateAtLeast: Double? = nil,
        timeout: TimeInterval
    ) -> ProbeSnap {
        waitForProbe(matching: { snap in
            if let titlePart, !snap.title.contains(titlePart) { return false }
            if let rateAtLeast, snap.rate < rateAtLeast { return false }
            return snap.duration > 0 || !snap.title.isEmpty
        }, timeout: timeout)
    }

    private func waitForProbe(
        matching predicate: (ProbeSnap) -> Bool,
        timeout: TimeInterval
    ) -> ProbeSnap {
        let deadline = Date().addingTimeInterval(timeout)
        var last = parseProbe()
        while Date() < deadline {
            last = parseProbe()
            if predicate(last) { return last }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return last
    }
}
