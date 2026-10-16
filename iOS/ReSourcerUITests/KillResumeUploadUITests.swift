//
//  KillResumeUploadUITests.swift
//  ReSourcerUITests
//
//  真实后端：分片上传只传第 0 片 → 杀 App → 冷启动 resume → 校验目标文件完整。
//

import XCTest

final class KillResumeUploadUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testKillAppThenResumeChunkUpload() throws {
        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY to run kill-resume upload UI E2E"
        )

        // Phase 1: 准备部分上传 job
        let app = XCUIApplication()
        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launchEnvironment["E2E_KILL_UPLOAD"] = "1"
        app.launch()

        let probe = app.descendants(matching: .any)["e2eUploadProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "upload probe should appear")

        let ready = waitForUploadProbe(in: app, prefix: "READY_TO_KILL|", timeout: 90)
        XCTAssertTrue(
            ready.hasPrefix("READY_TO_KILL|"),
            "phase1 should finish first chunk: \(ready)"
        )
        let parts = ready.split(separator: "|").map(String.init)
        XCTAssertGreaterThanOrEqual(parts.count, 3, "READY_TO_KILL|uploadId|fileName|jobId")

        // 杀进程（terminate，模拟用户强杀；job + staging 文件应仍在 Application Support）
        app.terminate()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        // Phase 2: 冷启动续传
        let app2 = XCUIApplication()
        app2.launchEnvironment["E2E_SERVER_URL"] = server!
        app2.launchEnvironment["E2E_API_KEY"] = key!
        app2.launchEnvironment["E2E_UPLOAD_RESUME_CHECK"] = "1"
        app2.launch()

        let probe2 = app2.descendants(matching: .any)["e2eUploadProbe"]
        XCTAssertTrue(probe2.waitForExistence(timeout: 15), "resume probe should appear")

        let done = waitForUploadProbe(in: app2, prefix: "RESUME_OK", timeout: 120)
        XCTAssertTrue(
            done.hasPrefix("RESUME_OK"),
            "resume should complete with intact file: \(done)"
        )
        XCTAssertEqual(app2.state, .runningForeground)
    }

    private func waitForUploadProbe(
        in app: XCUIApplication,
        prefix: String,
        timeout: TimeInterval
    ) -> String {
        let probe = app.descendants(matching: .any)["e2eUploadProbe"]
        let deadline = Date().addingTimeInterval(timeout)
        var last = ""
        while Date() < deadline {
            last = (probe.value as? String) ?? ""
            if last.hasPrefix(prefix) { return last }
            if last.hasPrefix("ERROR") || last.hasPrefix("RESUME_BAD") || last.hasPrefix("RESUME_LIST") {
                return last
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        return last
    }
}
