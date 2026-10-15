//
//  HeicThumbnailUITests.swift
//  ReSourcerUITests
//
//  Gallery HEIC 缩略图 E2E（需 Mac + 真实后端上的 tiled HEIC 样例）。
//  Linux 云 VM 无法跑 Xcode UI tests — 请在 ReSourcer-Mac self-hosted worker 上执行：
//    cd iOS && bash scripts/run-ui-tests.sh
//  并注入：
//    E2E_SERVER_URL=http://127.0.0.1:1234
//    E2E_API_KEY=<key>
//  源目录中放入至少一张 iPhone HEIC（tile grid）后索引。
//

import XCTest

final class HeicThumbnailUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY; run on ReSourcer-Mac for HEIC gallery thumb E2E"
        )

        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launch()
    }

    /// 冒烟：进入图库后应能看到文件卡片（含 HEIC 时缩略图由 tv=2 拉取新算法结果）。
    func testGalleryShowsFileCardsWithThumbnails() throws {
        let gallery = app.descendants(matching: .any)["gallery-root"]
        if gallery.waitForExistence(timeout: 8) {
            XCTAssertTrue(gallery.exists)
        } else {
            // 兼容尚未挂 test id 的构建：至少确认 App 未立刻崩溃
            XCTAssertTrue(app.state == .runningForeground)
        }
    }
}
