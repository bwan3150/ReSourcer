//
//  BackgroundPlaybackUITests.swift
//  ReSourcerUITests
//
//  后台播放相关的可自动化部分：预览内播放/暂停、上一个/下一个控件存在。
//  锁屏 Now Playing / 杀进程续传 → 见 docs/ios-background-impl.md 手动清单。
//
//  运行（macOS + Xcode）：
//    E2E_SERVER_URL=… E2E_API_KEY=… bash iOS/scripts/run-ui-tests.sh
//

import XCTest

final class BackgroundPlaybackUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY to run iOS background-playback UI E2E"
        )

        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launch()
    }

    private func openFirstPreviewIfPossible() -> Bool {
        let gridItem = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fileGridItem-")
        ).firstMatch
        if gridItem.waitForExistence(timeout: 15) {
            gridItem.tap()
            return true
        }
        return false
    }

    /// 预览 chrome 应提供上一个 / 下一个（远程命令复用同一导航路径）
    func testPreviewExposesPrevNextControls() throws {
        guard openFirstPreviewIfPossible() else {
            throw XCTSkip("No gallery file grid items — need indexed fixtures on the E2E server")
        }

        let prev = app.descendants(matching: .any)["previewPrevButton"]
        let next = app.descendants(matching: .any)["previewNextButton"]
        XCTAssertTrue(prev.waitForExistence(timeout: 10), "previewPrevButton should exist")
        XCTAssertTrue(next.waitForExistence(timeout: 5), "previewNextButton should exist")
    }

    /// 模式键存在：远程 prev/next 必须遵循同一 advance/shuffle/loop 状态（逻辑在主 App，此处确认控件可达）
    func testPlaybackModeButtonReachableForRemoteSkipContract() throws {
        guard openFirstPreviewIfPossible() else {
            throw XCTSkip("No gallery file grid items — need indexed fixtures on the E2E server")
        }

        let modeBtn = app.descendants(matching: .any)["playbackModeButton"]
        XCTAssertTrue(
            modeBtn.waitForExistence(timeout: 10),
            "playback mode button must exist so remote skip can respect advance/shuffle/loop"
        )
    }
}
