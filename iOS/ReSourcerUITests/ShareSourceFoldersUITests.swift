//
//  ShareSourceFoldersUITests.swift
//  ReSourcerUITests
//
//  真实后端 + App Group / Keychain 路径：主 App 按 Share Extension 同款客户端加载源文件夹。
//  （系统 Share Sheet UI 无法在 XCUITest 中稳定驱动，故用 E2E_SHARE_SOURCES_PROBE 探针。）
//
//  运行：
//    E2E_SERVER_URL=… E2E_API_KEY=… bash iOS/scripts/run-ui-tests.sh
//

import XCTest

final class ShareSourceFoldersUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY to run Share source-folder real-backend E2E"
        )

        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launchEnvironment["E2E_SHARE_SOURCES_PROBE"] = "1"
        app.launch()
    }

    /// App Group 镜像凭证后，ShareUploadClient 能拉到真实源文件夹；选择器文案含 URL
    func testSharePathLoadsSourceFoldersWithAppGroupCredentials() throws {
        let probe = app.descendants(matching: .any)["e2eShareSourcesProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 25), "share sources probe label should appear")

        var value = ""
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            value = probe.value as? String ?? probe.label
            if value.hasPrefix("OK:") || value.hasPrefix("ERROR:") { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        XCTAssertTrue(
            value.hasPrefix("OK:"),
            "Share Extension path must load source folders via App Group/Keychain; got: \(value)"
        )

        // OK:<count>|<activeURL>|<pickerLabel>|<paths>
        let parts = value.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        XCTAssertGreaterThanOrEqual(parts.count, 3, "probe payload incomplete: \(value)")

        if let count = Int(parts[0].replacingOccurrences(of: "OK:", with: "")) {
            XCTAssertGreaterThan(count, 0, "expected at least one source folder")
        } else {
            XCTFail("could not parse source count from \(value)")
        }

        let activeURL = parts[1]
        XCTAssertTrue(
            activeURL.contains("http://") || activeURL.contains("https://"),
            "active URL should be synced into App Group: \(activeURL)"
        )

        let pickerLabel = parts[2]
        // 名称 · URL — 或至少包含主机部分（空名称时仅为 URL）
        XCTAssertFalse(pickerLabel.isEmpty, "picker label must not be empty")
        XCTAssertTrue(
            pickerLabel.contains("127.0.0.1")
                || pickerLabel.contains("localhost")
                || pickerLabel.contains("·")
                || pickerLabel.contains(":"),
            "picker label must expose URL (public vs LAN): \(pickerLabel)"
        )
    }
}
