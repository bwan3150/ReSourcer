//
//  BackgroundSkipNonPlayableUITests.swift
//  ReSourcerUITests
//
//  混合图库：视频播完 / 遥控 next 须跳过图片等非音视频，后台连播不中断。
//

import XCTest

final class BackgroundSkipNonPlayableUITests: XCTestCase {

    /// 2s 视频，playlist 下一档为 gamma.png 等图片
    private let sampleVideoUUID = "ed062d4b-c01a-486d-b673-9b6ae1a288f3"
    /// 10s 带音轨视频（用于时长 ≫ 1 断言）
    private let bgVideoUUID = "8f845786-71ef-4bce-9797-6d4b6d1ced8a"

    private func launchApp(
        listLoop: String = "1",
        sameType: String = "0",
        advanceMode: String = "autoNext"
    ) throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY to run skip-non-playable E2E"
        )

        let app = XCUIApplication()
        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launchEnvironment["E2E_NOWPLAYING_PROBE"] = "1"
        app.launchEnvironment["E2E_LIST_LOOP"] = listLoop
        app.launchEnvironment["E2E_SHUFFLE"] = "0"
        app.launchEnvironment["E2E_SAME_TYPE"] = sameType
        // 默认 UserDefaults 是 repeatCurrent，不注入则播完不会 advanceToNext
        app.launchEnvironment["E2E_ADVANCE_MODE"] = advanceMode
        app.launch()
        return app
    }

    /// 从短视频 remote next：应跳过后续图片，落在可播放音视频上且仍在播
    func testRemoteNextSkipsImagesAndKeepsPlaying() throws {
        let app = try launchApp()
        try openVideo(uuid: sampleVideoUUID, in: app)

        var snap = waitForProbe(in: app, matching: { $0.rate > 0.3 && !$0.title.isEmpty }, timeout: 20)
        let first = snap.title
        XCTAssertTrue(
            first.contains("e2e-sample") || first.lowercased().hasSuffix(".mp4"),
            "should start on sample video: \(snap.raw)"
        )

        fireRemote(app, "next")
        snap = waitForProbe(
            in: app,
            matching: { !$0.title.isEmpty && $0.title != first && !$0.title.lowercased().hasSuffix(".png") && !$0.title.lowercased().hasSuffix(".heic") },
            timeout: 20
        )
        XCTAssertFalse(
            snap.title.lowercased().hasSuffix(".png") || snap.title.lowercased().hasSuffix(".heic"),
            "remote next must skip images: \(snap.raw)"
        )
        XCTAssertTrue(
            snap.title.lowercased().hasSuffix(".mp4")
                || snap.title.contains("e2e-bg-audio")
                || snap.title.contains("e2e-sample"),
            "should land on playable media: \(snap.raw)"
        )
        // 给新 item 一点缓冲时间
        snap = waitForProbe(in: app, matching: { $0.rate > 0.3 && !$0.title.isEmpty }, timeout: 15)
        XCTAssertGreaterThan(snap.rate, 0.3, "playback should continue after skipping images: \(snap.raw)")
    }

    /// 短视频自动播完后应跳过图片，不把 Now Playing 停在静图
    func testAutoAdvanceSkipsImagesAfterVideoEnds() throws {
        let app = try launchApp()
        try openVideo(uuid: sampleVideoUUID, in: app)

        var snap = waitForProbe(in: app, matching: { $0.rate > 0.3 && !$0.title.isEmpty }, timeout: 20)
        let first = snap.title

        // e2e-sample.mp4 ≈ 2s；等待结束 + skip
        snap = waitForProbe(
            in: app,
            matching: {
                !$0.title.isEmpty
                    && $0.title != first
                    && !$0.title.lowercased().hasSuffix(".png")
                    && !$0.title.lowercased().hasSuffix(".heic")
            },
            timeout: 25
        )
        XCTAssertNotEqual(snap.title, first, "should auto-advance off sample: \(snap.raw)")
        XCTAssertFalse(
            snap.title.lowercased().hasSuffix(".png") || snap.title.lowercased().hasSuffix(".heic"),
            "auto-advance must not stop on image: \(snap.raw)"
        )
    }

    /// Now Playing 总时长对多秒视频必须 ≫ 1
    func testNowPlayingDurationMuchGreaterThanOneSecond() throws {
        let app = try launchApp(listLoop: "0", sameType: "1")
        try openVideo(uuid: bgVideoUUID, in: app)

        let snap = waitForProbe(
            in: app,
            matching: { $0.duration > 5.0 && $0.rate > 0.3 && !$0.title.isEmpty },
            timeout: 25
        )
        XCTAssertGreaterThan(
            snap.duration, 5.0,
            "Now Playing duration must be real (≫1s) for multi-second video: \(snap.raw)"
        )
        XCTAssertGreaterThan(snap.elapsed, 0.05, "elapsed should advance: \(snap.raw)")
    }

    // MARK: - Helpers

    private func openVideo(uuid: String, in app: XCUIApplication) throws {
        let videoItem = app.descendants(matching: .any)["fileGridItem-\(uuid)"]
        guard videoItem.waitForExistence(timeout: 20) else {
            throw XCTSkip("Missing fileGridItem-\(uuid) — seed fixtures and reindex")
        }
        videoItem.tap()
        let playPause = app.descendants(matching: .any)["previewPlayPauseButton"]
        if !playPause.waitForExistence(timeout: 4) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(playPause.waitForExistence(timeout: 12), "preview chrome")
    }

    private func fireRemote(_ app: XCUIApplication, _ cmd: String) {
        let nonce = Int(Date().timeIntervalSince1970 * 1000)
        let url = URL(string: "resourcer://e2e/np?cmd=\(cmd)&n=\(nonce)")!
        XCUIDevice.shared.system.open(url)
        RunLoop.current.run(until: Date().addingTimeInterval(0.55))
        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    }

    private struct ProbeSnap {
        let raw: String
        let title: String
        let duration: Double
        let elapsed: Double
        let rate: Double
    }

    private func parseProbe(in app: XCUIApplication) -> ProbeSnap {
        let probe = app.descendants(matching: .any)["e2eNowPlayingProbe"]
        let raw = probe.value as? String ?? probe.label
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        // OK|title|dur|el|rate|...
        let title = parts.count > 1 ? parts[1] : ""
        let duration = parts.count > 2 ? Double(parts[2]) ?? 0 : 0
        let elapsed = parts.count > 3 ? Double(parts[3]) ?? 0 : 0
        let rate = parts.count > 4 ? Double(parts[4]) ?? 0 : 0
        return ProbeSnap(raw: raw, title: title, duration: duration, elapsed: elapsed, rate: rate)
    }

    private func waitForProbe(
        in app: XCUIApplication,
        matching: (ProbeSnap) -> Bool,
        timeout: TimeInterval
    ) -> ProbeSnap {
        let deadline = Date().addingTimeInterval(timeout)
        var last = parseProbe(in: app)
        while Date() < deadline {
            last = parseProbe(in: app)
            if matching(last) { return last }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return last
    }
}
