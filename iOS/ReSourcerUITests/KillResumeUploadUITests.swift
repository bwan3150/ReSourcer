//
//  KillResumeUploadUITests.swift
//  ReSourcerUITests
//
//  真实后端：大文件分片上传中途杀 App → 冷启动 resume → 文件字节完整。
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

        // Phase 1: ~12MB，先传 2/12 片再杀
        let app = XCUIApplication()
        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launchEnvironment["E2E_KILL_UPLOAD"] = "1"
        app.launchEnvironment["E2E_KILL_UPLOAD_MB"] = "12"
        app.launchEnvironment["E2E_KILL_CHUNKS_BEFORE"] = "2"
        app.launch()

        let probe = app.descendants(matching: .any)["e2eUploadProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 15), "upload probe should appear")

        let ready = waitForUploadProbe(in: app, prefix: "READY_TO_KILL|", timeout: 180)
        XCTAssertTrue(
            ready.hasPrefix("READY_TO_KILL|"),
            "phase1 should finish first chunks mid-upload: \(ready)"
        )
        let parts = ready.split(separator: "|").map(String.init)
        // READY_TO_KILL|uploadId|fileName|jobId|totalBytes|2/12
        XCTAssertGreaterThanOrEqual(parts.count, 5, ready)
        let expectedBytes = Int(parts[4]) ?? 0
        XCTAssertGreaterThanOrEqual(expectedBytes, 12 * 1024 * 1024, "large upload payload: \(ready)")
        if parts.count >= 6 {
            XCTAssertTrue(parts[5].contains("/"), "chunk progress \(parts[5])")
            let prog = parts[5].split(separator: "/")
            if prog.count == 2, let done = Int(prog[0]), let total = Int(prog[1]) {
                XCTAssertGreaterThan(total, done, "must kill mid-upload, not after complete")
                XCTAssertGreaterThanOrEqual(done, 1)
            }
        }

        app.terminate()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        // Phase 2: 冷启动续传并校验精确字节数
        let app2 = XCUIApplication()
        app2.launchEnvironment["E2E_SERVER_URL"] = server!
        app2.launchEnvironment["E2E_API_KEY"] = key!
        app2.launchEnvironment["E2E_UPLOAD_RESUME_CHECK"] = "1"
        app2.launch()

        let probe2 = app2.descendants(matching: .any)["e2eUploadProbe"]
        XCTAssertTrue(probe2.waitForExistence(timeout: 15), "resume probe should appear")

        let done = waitForUploadProbe(in: app2, prefix: "RESUME_OK|", timeout: 300)
        XCTAssertTrue(
            done.hasPrefix("RESUME_OK|"),
            "resume should complete with intact file: \(done)"
        )
        let doneParts = done.split(separator: "|").map(String.init)
        XCTAssertGreaterThanOrEqual(doneParts.count, 3, done)
        let actualSize = Int(doneParts[2]) ?? -1
        XCTAssertEqual(actualSize, expectedBytes, "server file size must match: \(done)")
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
            if last.hasPrefix("ERROR") || last.hasPrefix("RESUME_BAD") || last.hasPrefix("RESUME_LIST")
                || last.hasPrefix("RESUME_NOTHING") || last.hasPrefix("RESUME_OK_NO_FILE") {
                return last
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return last
    }
}
