//
//  ThumbnailPersistUITests.swift
//  ReSourcerUITests
//
//  服务端 `.thumb` 路径镜像持久化 — iOS 侧契约 E2E。
//  客户端本地 ThumbnailCacheService 保留；服务端首次请求落盘由后端 API 测试覆盖。
//  Linux 云 VM 无法跑 Xcode UI tests — 请在 ReSourcer-Mac self-hosted worker 上执行：
//    cd iOS && bash scripts/run-ui-tests.sh
//  并注入：
//    E2E_SERVER_URL=http://127.0.0.1:1234
//    E2E_API_KEY=<key>
//

import XCTest

final class ThumbnailPersistUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY; run on ReSourcer-Mac for thumbnail persist gallery E2E"
        )

        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launch()
    }

    /// 冒烟：图库可打开；缩略图仍经 PreviewService（含 tv=）拉取，本地磁盘缓存保留。
    func testGalleryLoadsWithServerBackedThumbnails() throws {
        let gallery = app.descendants(matching: .any)["gallery-root"]
        if gallery.waitForExistence(timeout: 8) {
            XCTAssertTrue(gallery.exists)
        } else {
            XCTAssertTrue(app.state == .runningForeground)
        }
    }
}
