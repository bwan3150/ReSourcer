//
//  ShareUploadPathUITests.swift
//  ReSourcerUITests
//
//  覆盖 Share Extension 实际上传路径：App Group sharedContainer + 前台 multipart。
//  回归 NSURLErrorDomain -995（BackgroundSessionRequiresSharedContainer）。
//  系统 Share Sheet 无法在 XCUITest 稳定驱动，故用 E2E_SHARE_UPLOAD_PROBE。
//

import XCTest

final class ShareUploadPathUITests: XCTestCase {

    func testShareUploadPathUsesSharedContainerAndForegroundMultipart() throws {
        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY to run Share upload-path E2E"
        )

        let app = XCUIApplication()
        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launchEnvironment["E2E_SHARE_UPLOAD_PROBE"] = "1"
        app.launch()

        let probe = app.descendants(matching: .any)["e2eShareUploadProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 25), "share upload probe should appear")

        var value = ""
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            value = probe.value as? String ?? probe.label
            if value.hasPrefix("OK:") || value.hasPrefix("ERROR:") { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        XCTAssertTrue(
            value.hasPrefix("OK:"),
            "Share upload path must succeed without -995; got: \(value)"
        )
        XCTAssertFalse(
            value.contains("code=-995") || value.lowercased().contains("sharedcontainer"),
            "must not hit BackgroundSessionRequiresSharedContainer: \(value)"
        )
        XCTAssertTrue(
            value.contains("shared=group.app.resourcer.apple"),
            "probe must confirm App Group sharedContainerIdentifier: \(value)"
        )
    }
}
