//
//  ShareOriginalFormatUITests.swift
//  ReSourcerUITests
//
//  Share 上传路径原样字节：HEIC / MOV 不经 UIImage 重编码。
//  系统 Share Sheet 无法稳定驱动，故复用 ShareUploadClient 探针（与 Extension 同款上传客户端）。
//

import XCTest

final class ShareOriginalFormatUITests: XCTestCase {

    func testShareUploadPreservesHEICAndMOVBytes() throws {
        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]
        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY for original-format upload E2E"
        )

        let heic = env["E2E_HEIC_SAMPLE_PATH"]
            ?? "/tmp/share-originals-e2e/with_meta_real.heic"
        let mov = env["E2E_MOV_SAMPLE_PATH"]
            ?? "/tmp/share-originals-e2e/sample.mov"

        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: heic),
            "HEIC sample missing at \(heic)"
        )

        let app = XCUIApplication()
        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launchEnvironment["E2E_SHARE_ORIGINAL_UPLOAD_PROBE"] = "1"
        app.launchEnvironment["E2E_HEIC_SAMPLE_PATH"] = heic
        if FileManager.default.fileExists(atPath: mov) {
            app.launchEnvironment["E2E_MOV_SAMPLE_PATH"] = mov
        }
        app.launch()

        let probe = app.descendants(matching: .any)["e2eShareOriginalUploadProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 30), "original upload probe should appear")

        var value = ""
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            value = probe.value as? String ?? probe.label
            if value.contains("HEIC:") && (value.contains("MOV:") || value.contains("HEIC:OK") || value.contains("HEIC:FAIL") || value.contains("ERROR:")) {
                if value.hasPrefix("ERROR:") || value.contains("HEIC:OK") || value.contains("HEIC:FAIL") {
                    break
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        XCTAssertFalse(value.hasPrefix("ERROR:"), "probe error: \(value)")
        XCTAssertTrue(value.contains("HEIC:OK"), "HEIC must upload byte-identical; got: \(value)")
        XCTAssertTrue(
            value.contains("magic=heic") || value.contains("magic=mif1") || value.contains("magic=heic"),
            "stored HEIC magic/brand should remain HEIC family: \(value)"
        )

        if FileManager.default.fileExists(atPath: mov) {
            XCTAssertTrue(value.contains("MOV:OK"), "MOV must upload byte-identical; got: \(value)")
            XCTAssertTrue(
                value.contains("magic=qt") || value.contains("ext=mov"),
                "MOV container should stay QuickTime: \(value)"
            )
        }
    }
}
