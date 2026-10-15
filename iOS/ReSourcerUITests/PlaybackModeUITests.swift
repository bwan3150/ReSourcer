//
//  PlaybackModeUITests.swift
//  ReSourcerUITests
//
//  播放模式 / 队列面板 E2E。
//  需要可用的后端并注入：
//    E2E_SERVER_URL=http://127.0.0.1:1234
//    E2E_API_KEY=<key>
//  以及测试源目录里至少 2 个已索引文件。
//
//  运行（macOS + Xcode）：
//    cd iOS && bash scripts/run-ui-tests.sh
//

import XCTest

final class PlaybackModeUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? ProcessInfo.processInfo.environment["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? ProcessInfo.processInfo.environment["RESOURCER_E2E_KEY"]

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY to run iOS playback UI E2E against a live server"
        )

        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launch()
    }

    /// Open first file grid item into preview if possible.
    private func openFirstPreviewIfPossible() -> Bool {
        // Prefer accessibility ids stamped on grid items
        let gridItem = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fileGridItem-")
        ).firstMatch
        if gridItem.waitForExistence(timeout: 15) {
            gridItem.tap()
            return true
        }
        return false
    }

    func testModeButtonExistsAndTogglesAdvanceLabel() throws {
        guard openFirstPreviewIfPossible() else {
            throw XCTSkip("No gallery file grid items — need indexed fixtures on the E2E server")
        }

        let modeBtn = app.images["playbackModeButton"]
        // Image may be exposed as button depending on hit testing
        let btn = modeBtn.exists ? modeBtn : app.buttons["playbackModeButton"]
        XCTAssertTrue(btn.waitForExistence(timeout: 10), "playback mode button should appear in preview chrome")

        let before = btn.label
        btn.tap()
        // Label should flip between 单曲循环 / 自动下一个
        let after = btn.label
        XCTAssertNotEqual(before, after, "tap should toggle advance mode accessibility label")
        btn.tap() // restore
    }

    func testLongPressOpensQueuePanelWithIndependentSwitches() throws {
        guard openFirstPreviewIfPossible() else {
            throw XCTSkip("No gallery file grid items — need indexed fixtures on the E2E server")
        }

        let modeBtn = app.descendants(matching: .any)["playbackModeButton"]
        XCTAssertTrue(modeBtn.waitForExistence(timeout: 10))
        modeBtn.press(forDuration: 0.8)

        let panel = app.descendants(matching: .any)["queuePanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "queue panel should open on long-press")

        XCTAssertTrue(app.switches["queueShuffleToggle"].waitForExistence(timeout: 3)
            || app.descendants(matching: .any)["queueShuffleToggle"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["queueListLoopToggle"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["queueSameTypeToggle"].exists)
    }
}
