//
//  ShareDownloadUITests.swift
//  ReSourcerUITests
//
//  Flow A：深链 / App Group pending URL → 下载 Tab 仅预填，不自动 detect、不自动下载。
//
//  运行（macOS + Xcode / ReSourcer-Mac）：
//    E2E_SERVER_URL=... E2E_API_KEY=... bash iOS/scripts/run-ui-tests.sh
//  或仅本文件：
//    xcodebuild ... -only-testing:ReSourcerUITests/ShareDownloadUITests
//
//  Share Sheet 真机手动清单见 docs/ios-share-extension-impl.md
//

import XCTest

final class ShareDownloadUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY to run iOS share-download UI E2E"
        )

        let pending = "https://example.com/e2e-share-prefill-video"
        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launchEnvironment["E2E_PENDING_DOWNLOAD_URL"] = pending
        app.launch()
    }

    /// 启动时注入 pending URL → 应落在下载 Tab 且输入框等于该 URL
    func testPendingShareURLPrefillsDownloadField() throws {
        let pending = "https://example.com/e2e-share-prefill-video"

        // 切到下载 Tab（若启动逻辑已切过去则仍可点）
        let downloadTab = app.tabBars.buttons["下载"]
        if downloadTab.waitForExistence(timeout: 12) {
            downloadTab.tap()
        }

        let field = app.textFields["downloadURLField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "download URL field should exist")

        // 等待预填（App onAppear → consume → DownloadView apply）
        var value = ""
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            value = field.value as? String ?? ""
            if value == pending { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(value, pending, "URL field should be prefilled from share handoff")

        // 不应自动开始下载：下载按钮可点但未进入「创建中」转圈后清空
        // 预填后输入框仍保留 pending（自动下载会清空）
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let after = field.value as? String ?? ""
        XCTAssertEqual(after, pending, "prefill must not auto-start download (field stays filled)")
    }

    /// 深链 resourcer://download?url=…（若模拟器允许 openURL）
    func testDeepLinkPrefillsDownloadField() throws {
        let pending = "https://example.com/e2e-deeplink-prefill"
        // 先确保已登录主界面
        let downloadTab = app.tabBars.buttons["下载"]
        XCTAssertTrue(downloadTab.waitForExistence(timeout: 12))

        let url = URL(string: "resourcer://download?url=\(pending.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)")!
        // XCUIApplication.open 走系统打开 URL（模拟 Share / 深链交接）
        app.open(url)

        if downloadTab.waitForExistence(timeout: 5) {
            downloadTab.tap()
        }

        let field = app.textFields["downloadURLField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))

        var value = ""
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            value = field.value as? String ?? ""
            if value.contains("e2e-deeplink-prefill") { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(
            value.contains("e2e-deeplink-prefill"),
            "deep link should prefill download field, got: \(value)"
        )
    }
}
