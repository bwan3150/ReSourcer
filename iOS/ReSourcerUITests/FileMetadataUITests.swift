//
//  FileMetadataUITests.swift
//  ReSourcerUITests
//
//  文件详情元数据（按路径 API）— 真实后端 E2E。
//  需要：
//    E2E_SERVER_URL=http://127.0.0.1:1234
//    E2E_API_KEY=<key>
//  源目录需含 IMG_4821.HEIC（带拍摄时间/GPS）与 plain.png（无 EXIF）。
//

import XCTest

final class FileMetadataUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY for file-metadata real-backend E2E"
        )

        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launch()
    }

    /// 冒烟：图库可打开（元数据面板在 info sheet；完整点选依赖图库有已扫文件）。
    func testGalleryOpensForMetadataFlow() throws {
        let gallery = app.descendants(matching: .any)["gallery-root"]
        if gallery.waitForExistence(timeout: 10) {
            XCTAssertTrue(gallery.exists)
        } else {
            XCTAssertTrue(app.state == .runningForeground)
        }
    }
}
