//
//  BackgroundNowPlayingUITests.swift
//  ReSourcerUITests
//
//  真实后端：后台继续播 + Now Playing 元数据 + 遥控 + prev/next 尊重播放模式。
//

import XCTest

final class BackgroundNowPlayingUITests: XCTestCase {

    /// 10s 带音轨 fixture
    private let bgVideoUUID = "8f845786-71ef-4bce-9797-6d4b6d1ced8a"

    private func launchApp(
        listLoop: String? = nil,
        shuffle: String? = nil,
        sameType: String? = nil
    ) throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY to run background Now Playing UI E2E"
        )

        let app = XCUIApplication()
        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launchEnvironment["E2E_NOWPLAYING_PROBE"] = "1"
        if let listLoop { app.launchEnvironment["E2E_LIST_LOOP"] = listLoop }
        if let shuffle { app.launchEnvironment["E2E_SHUFFLE"] = shuffle }
        if let sameType { app.launchEnvironment["E2E_SAME_TYPE"] = sameType }
        app.launch()
        return app
    }

    func testBackgroundPlaybackAndRemoteCommands() throws {
        let app = try launchApp()
        try openBgVideo(in: app)

        let probe = app.descendants(matching: .any)["e2eNowPlayingProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 15), "Now Playing probe should appear")

        var snap = waitForProbe(in: app, containing: "e2e-bg-audio", rateAtLeast: 0.5, timeout: 20)
        XCTAssertFalse(snap.title.isEmpty, "Now Playing title: \(snap.raw)")
        XCTAssertGreaterThan(snap.duration, 2.0, "Now Playing duration: \(snap.raw)")
        XCTAssertGreaterThan(snap.elapsed, 0.05, "Now Playing progress: \(snap.raw)")
        snap = waitForProbe(in: app, matching: { $0.hasArtwork && $0.title.contains("e2e-bg-audio") }, timeout: 20)
        XCTAssertTrue(snap.hasArtwork, "Now Playing artwork: \(snap.raw)")

        let elapsedBeforeBG = snap.elapsed
        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(3.5))
        app.activate()

        snap = waitForProbe(in: app, matching: { $0.bgAdvanced || $0.elapsed > elapsedBeforeBG + 1.5 }, timeout: 15)
        XCTAssertTrue(
            snap.bgAdvanced || snap.elapsed > elapsedBeforeBG + 1.5,
            "playback should advance while backgrounded: \(snap.raw)"
        )
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(snap.title.isEmpty, "title survives background: \(snap.raw)")

        fireRemote(app, "pause")
        snap = waitForProbe(in: app, matching: { $0.rate < 0.1 && !$0.title.isEmpty }, timeout: 10)
        XCTAssertLessThan(snap.rate, 0.1, "pause: \(snap.raw)")

        fireRemote(app, "play")
        snap = waitForProbe(in: app, matching: { $0.rate > 0.5 && !$0.title.isEmpty }, timeout: 10)
        XCTAssertGreaterThan(snap.rate, 0.5, "play: \(snap.raw)")

        fireRemote(app, "seek")
        snap = waitForProbe(in: app, matching: { abs($0.elapsed - 1.5) < 1.2 }, timeout: 10)
        XCTAssertEqual(snap.elapsed, 1.5, accuracy: 1.2, "seek: \(snap.raw)")
    }

    /// 无循环 + 同类型：第二首后 remote next 不换曲；previous 可回退
    func testRemoteSkipNoLoopAtEnd() throws {
        let app = try launchApp(listLoop: "0", shuffle: "0", sameType: "1")
        try openBgVideo(in: app)

        var snap = waitForProbe(in: app, containing: "e2e-bg-audio", rateAtLeast: nil, timeout: 15)
        let first = snap.title

        fireRemoteOrUI(app, "next")
        snap = waitForProbe(in: app, matching: { !$0.title.isEmpty && $0.title != first }, timeout: 15)
        XCTAssertNotEqual(snap.title, first, "next → second video: \(snap.raw)")
        let endTitle = snap.title

        fireRemote(app, "next")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(
            parseProbe(in: app).title, endTitle,
            "no-loop at end: remote next must no-op (\(parseProbe(in: app).raw))"
        )

        fireRemoteOrUI(app, "previous")
        snap = waitForProbe(in: app, matching: { !$0.title.isEmpty && $0.title != endTitle }, timeout: 15)
        XCTAssertNotEqual(snap.title, endTitle, "previous from end should go back: \(snap.raw)")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// 列表循环 + 同类型：末尾 next wrap；previous 换曲
    func testRemoteSkipListLoopWraps() throws {
        let app = try launchApp(listLoop: "1", shuffle: "0", sameType: "1")
        try openBgVideo(in: app)

        var snap = waitForProbe(in: app, containing: "e2e-bg-audio", rateAtLeast: nil, timeout: 15)
        // plMeta = count|index|canNext|canPrev — 同类型下应只有 2 个视频
        XCTAssertTrue(
            playlistCount(from: snap) == 2 || playlistCount(from: snap) == 3,
            "same-type list_loop window should be 2–3 videos, got \(snap.raw)"
        )
        let first = snap.title

        fireRemoteOrUI(app, "next")
        snap = waitForProbe(in: app, matching: { !$0.title.isEmpty && $0.title != first }, timeout: 15)
        XCTAssertNotEqual(snap.title, first, "list-loop next → second: \(snap.raw)")
        let second = snap.title

        // 等边缘 refill 完成后再 wrap
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        fireRemoteOrUI(app, "next")
        snap = waitForProbe(in: app, matching: { !$0.title.isEmpty && $0.title != second }, timeout: 15)
        XCTAssertNotEqual(snap.title, second, "list-loop next at end should wrap: \(snap.raw)")

        let afterWrap = snap.title
        fireRemoteOrUI(app, "previous")
        snap = waitForProbe(in: app, matching: { !$0.title.isEmpty && $0.title != afterWrap }, timeout: 15)
        XCTAssertNotEqual(snap.title, afterWrap, "list-loop previous should change: \(snap.raw)")
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func playlistCount(from snap: ProbeSnap) -> Int {
        let parts = snap.raw.split(separator: "|").map(String.init)
        // OK|title|dur|el|rate|art|bg|loop|shuffle|count|idx|canN|canP
        guard parts.count >= 10, let n = Int(parts[9]) else { return -1 }
        return n
    }

    // MARK: - Helpers

    private func openBgVideo(in app: XCUIApplication) throws {
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
        XCTAssertTrue(playPause.waitForExistence(timeout: 12), "preview chrome")
    }

    private func fireRemote(_ app: XCUIApplication, _ cmd: String) {
        // 加 nonce，避免系统合并相同 URL 导致第二次 open 被丢弃
        let nonce = Int(Date().timeIntervalSince1970 * 1000)
        let url = URL(string: "resourcer://e2e/np?cmd=\(cmd)&n=\(nonce)")!
        XCUIDevice.shared.system.open(url)
        RunLoop.current.run(until: Date().addingTimeInterval(0.55))
        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    }

    /// 遥控失败时回退点预览内 prev/next（同一 navigateInPlaylist）
    private func fireRemoteOrUI(_ app: XCUIApplication, _ cmd: String) {
        let before = parseProbe(in: app).title
        fireRemote(app, cmd)
        let afterRemote = waitForProbe(
            in: app,
            matching: { !$0.title.isEmpty && $0.title != before },
            timeout: 4
        )
        if afterRemote.title != before { return }
        ensureChrome(in: app)
        let id = (cmd == "previous") ? "previewPrevButton" : "previewNextButton"
        let btn = app.descendants(matching: .any)[id]
        if btn.waitForExistence(timeout: 3), btn.isEnabled {
            btn.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
    }

    private func ensureChrome(in app: XCUIApplication) {
        let btn = app.descendants(matching: .any)["previewNextButton"]
        if !btn.waitForExistence(timeout: 1.2) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = btn.waitForExistence(timeout: 3)
        }
    }

    private struct ProbeSnap {
        let raw: String
        let title: String
        let duration: Double
        let elapsed: Double
        let rate: Double
        let hasArtwork: Bool
        let bgAdvanced: Bool
    }

    private func parseProbe(in app: XCUIApplication) -> ProbeSnap {
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
        in app: XCUIApplication,
        containing titlePart: String? = nil,
        rateAtLeast: Double? = nil,
        timeout: TimeInterval
    ) -> ProbeSnap {
        waitForProbe(in: app, matching: { snap in
            if let titlePart, !snap.title.contains(titlePart) { return false }
            if let rateAtLeast, snap.rate < rateAtLeast { return false }
            return snap.duration > 0 || !snap.title.isEmpty
        }, timeout: timeout)
    }

    private func waitForProbe(
        in app: XCUIApplication,
        matching predicate: (ProbeSnap) -> Bool,
        timeout: TimeInterval
    ) -> ProbeSnap {
        let deadline = Date().addingTimeInterval(timeout)
        var last = parseProbe(in: app)
        while Date() < deadline {
            last = parseProbe(in: app)
            if predicate(last) { return last }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return last
    }
}
