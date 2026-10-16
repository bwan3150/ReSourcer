//
//  ShareLinkHandoffUITests.swift
//  ReSourcerUITests
//
//  Flow A 扩展：分享链接时选定服务器 + 源文件夹 → 主 App 切换后预填下载 URL。
//  覆盖：普通源 / 私密源解锁成功 / 私密源解锁取消。
//

import XCTest

final class ShareLinkHandoffUITests: XCTestCase {

    private var serverURL: String!
    private var apiKey: String!
    private var sourceFolder: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]
        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY for share link handoff E2E"
        )
        serverURL = server!
        apiKey = key!

        // 通过 API 拿真实源路径（与 Share Extension 同源）
        sourceFolder = try fetchCurrentSourceFolder()
    }

    /// 普通源：切换到指定源后进入下载页，URL 预填且不自动下载
    func testNormalSourceHandoffPrefillsWithoutAutoDownload() throws {
        let pending = "https://www.youtube.com/watch?v=e2eShareLinkNormal"
        let app = XCUIApplication()
        app.launchEnvironment["E2E_SERVER_URL"] = serverURL
        app.launchEnvironment["E2E_API_KEY"] = apiKey
        app.launchEnvironment["E2E_PENDING_DOWNLOAD_URL"] = pending
        app.launchEnvironment["E2E_SHARE_HANDOFF_SOURCE"] = sourceFolder
        // 确保该路径不被视为私密残留
        app.launch()

        let probe = app.descendants(matching: .any)["e2eShareHandoffProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 20))
        let probeValue = waitProbe(probe, prefix: "OK:", timeout: 15)
        XCTAssertTrue(probeValue.hasPrefix("OK:"), "handoff probe: \(probeValue)")
        XCTAssertTrue(probeValue.contains(sourceFolder), "probe should include source: \(probeValue)")
        XCTAssertTrue(probeValue.contains(pending), "probe should include url: \(probeValue)")

        let downloadTab = app.tabBars.buttons["下载"]
        if downloadTab.waitForExistence(timeout: 8) {
            downloadTab.tap()
        }
        let field = app.textFields["downloadURLField"]
        XCTAssertTrue(field.waitForExistence(timeout: 12))
        let value = waitField(field, equals: pending, timeout: 10)
        XCTAssertEqual(value, pending)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        XCTAssertEqual(field.value as? String ?? "", pending, "must not auto-download/clear")
    }

    /// 私密源 + 解锁成功 → 进入下载页并预填
    func testPrivateSourceUnlockSuccessPrefillsDownload() throws {
        let pending = "https://x.com/e2e/share-private-ok"
        let app = XCUIApplication()
        app.launchEnvironment["E2E_SERVER_URL"] = serverURL
        app.launchEnvironment["E2E_API_KEY"] = apiKey
        app.launchEnvironment["E2E_PENDING_DOWNLOAD_URL"] = pending
        app.launchEnvironment["E2E_SHARE_HANDOFF_SOURCE"] = sourceFolder
        app.launchEnvironment["E2E_PRIVATE_SOURCE_FOLDER"] = sourceFolder
        app.launchEnvironment["E2E_PRIVACY_PATTERN"] = "0-1-2-4-5"
        app.launchEnvironment["E2E_SHARE_PRIVACY_AUTO"] = "success"
        app.launch()

        let probe = app.descendants(matching: .any)["e2eShareHandoffProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 20))
        // 先应进入等待解锁，再被 AUTO=success 推进到 OK
        let mid = waitProbe(probe, prefixes: ["WAITING_UNLOCK:", "OK:"], timeout: 12)
        XCTAssertTrue(
            mid.hasPrefix("WAITING_UNLOCK:") || mid.hasPrefix("OK:"),
            "should hit unlock gate or finish; got \(mid)"
        )
        let probeValue = waitProbe(probe, prefixes: ["OK:"], timeout: 15)
        XCTAssertTrue(probeValue.hasPrefix("OK:"), "after unlock: \(probeValue)")
        XCTAssertTrue(probeValue.contains(pending), probeValue)

        let field = app.textFields["downloadURLField"]
        XCTAssertTrue(field.waitForExistence(timeout: 12))
        XCTAssertEqual(waitField(field, equals: pending, timeout: 10), pending)
    }

    /// 私密源 + 解锁取消 → 不得进入该私密源的下载预填流
    func testPrivateSourceUnlockCancelDoesNotEnterDownload() throws {
        let pending = "https://x.com/e2e/share-private-cancel"
        let app = XCUIApplication()
        app.launchEnvironment["E2E_SERVER_URL"] = serverURL
        app.launchEnvironment["E2E_API_KEY"] = apiKey
        app.launchEnvironment["E2E_PENDING_DOWNLOAD_URL"] = pending
        app.launchEnvironment["E2E_SHARE_HANDOFF_SOURCE"] = sourceFolder
        app.launchEnvironment["E2E_PRIVATE_SOURCE_FOLDER"] = sourceFolder
        app.launchEnvironment["E2E_PRIVACY_PATTERN"] = "0-1-2-4-5"
        app.launchEnvironment["E2E_SHARE_PRIVACY_AUTO"] = "cancel"
        app.launch()

        let probe = app.descendants(matching: .any)["e2eShareHandoffProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 20))
        let probeValue = waitProbe(probe, prefixes: ["CANCELLED:", "WAITING_UNLOCK:"], timeout: 15)
        // AUTO=cancel 最终应为 CANCELLED
        let finalValue = waitProbe(probe, prefixes: ["CANCELLED:"], timeout: 12)
        XCTAssertTrue(
            finalValue.hasPrefix("CANCELLED:"),
            "cancel probe expected CANCELLED; mid=\(probeValue) final=\(finalValue)"
        )

        // 下载框不应被预填为该 pending（取消后已 clear）
        let downloadTab = app.tabBars.buttons["下载"]
        if downloadTab.waitForExistence(timeout: 8) {
            downloadTab.tap()
        }
        let field = app.textFields["downloadURLField"]
        if field.waitForExistence(timeout: 8) {
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            let value = field.value as? String ?? ""
            XCTAssertFalse(
                value.contains("share-private-cancel"),
                "cancelled unlock must not prefill private-folder download URL; got \(value)"
            )
        }
    }

    // MARK: - Helpers

    private func fetchCurrentSourceFolder() throws -> String {
        let url = URL(string: serverURL.hasSuffix("/") ? serverURL + "api/config/sources" : serverURL + "/api/config/sources")!
        var req = URLRequest(url: url)
        req.setValue("api_key=\(apiKey!)", forHTTPHeaderField: "Cookie")
        let sem = DispatchSemaphore(value: 0)
        var result: String?
        var err: Error?
        URLSession.shared.dataTask(with: req) { data, _, error in
            defer { sem.signal() }
            if let error { err = error; return }
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = obj["current"] as? String, !current.isEmpty else {
                err = NSError(domain: "ShareLinkHandoff", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad sources response"])
                return
            }
            result = current
        }.resume()
        _ = sem.wait(timeout: .now() + 15)
        if let err { throw err }
        guard let result else {
            throw NSError(domain: "ShareLinkHandoff", code: 2, userInfo: [NSLocalizedDescriptionKey: "no source"])
        }
        return result
    }

    private func waitProbe(_ element: XCUIElement, prefix: String, timeout: TimeInterval) -> String {
        waitProbe(element, prefixes: [prefix], timeout: timeout)
    }

    private func waitProbe(_ element: XCUIElement, prefixes: [String], timeout: TimeInterval) -> String {
        var value = ""
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            value = element.value as? String ?? element.label
            if prefixes.contains(where: { value.hasPrefix($0) }) { return value }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return value
    }

    private func waitField(_ field: XCUIElement, equals expected: String, timeout: TimeInterval) -> String {
        var value = ""
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            value = field.value as? String ?? ""
            if value == expected { return value }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return value
    }
}
