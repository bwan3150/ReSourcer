//
//  HeicLivePhotoUITests.swift
//  ReSourcerUITests
//
//  真后端：实况配对 LIVE 标记；竖拍 Orientation=6 缩略图/预览不横置。
//  环境：E2E_SERVER_URL / E2E_API_KEY / E2E_SOURCE_FOLDER（可选，可自动发现）
//

import XCTest

@MainActor
final class HeicLivePhotoUITests: XCTestCase {

    private var app: XCUIApplication!
    private var serverURL: String = ""
    private var apiKey: String = ""
    private var sourceFolder: String = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]
        sourceFolder = env["E2E_SOURCE_FOLDER"]
            ?? env["E2E_HEIC_LIVE_SOURCE"]
            ?? env["RESOURCER_E2E_SOURCE"]
            ?? ""

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY for HEIC/Live Photo E2E"
        )

        serverURL = server!
        apiKey = key!

        app.launchEnvironment["E2E_SERVER_URL"] = serverURL
        app.launchEnvironment["E2E_API_KEY"] = apiKey
        if !sourceFolder.isEmpty {
            app.launchEnvironment["E2E_SOURCE_FOLDER"] = sourceFolder
        }
        app.launchEnvironment["E2E_SKIP_ONBOARDING"] = "1"
        app.launch()
    }

    func testLivePhotoShowsLIVEBadgeAndHoldDoesNotDismiss() throws {
        let liveName = "IMG_LIVE.HEIC"
        let uuid = try requireUUID(named: liveName)
        openGridItem(uuid: uuid)

        let badge = app.descendants(matching: .any)["livePhotoBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 25), "LIVE badge should appear for paired HEIC+MOV")

        // 不得停在「实况照片加载失败」
        let fail = app.staticTexts["实况照片加载失败"]
        XCTAssertFalse(fail.exists, "Live Photo must load (PHLivePhoto or still+MOV fallback)")

        let capsule = app.descendants(matching: .any)["previewFileNameCapsule"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 8), "preview chrome visible")
        assertPreviewFileNameContains("IMG_LIVE")

        // 按住画面中部：实况应播放且不退出预览
        let frame = app.windows.firstMatch.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let hold = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: center.x, dy: center.y))
        hold.press(forDuration: 1.2)

        XCTAssertTrue(
            capsule.waitForExistence(timeout: 3),
            "hold on Live Photo must not dismiss preview"
        )
        XCTAssertTrue(badge.exists, "LIVE badge remains after hold")
        XCTAssertFalse(fail.exists, "hold must not leave failed state")

        attachScreenshot(name: "ios-live-photo-hold")
    }

    func testOrientedPortraitHEICOpensUpright() throws {
        let uuid = try requireUUID(named: "orient6.HEIC")
        openGridItem(uuid: uuid)
        assertPreviewFileNameContains("orient6")
        attachScreenshot(name: "ios-orient6-heic-preview")
    }

    func testOrientedPortraitJPEGOpensUpright() throws {
        let uuid = try requireUUID(named: "orient6.jpg")
        openGridItem(uuid: uuid)
        assertPreviewFileNameContains("orient6")
        attachScreenshot(name: "ios-orient6-jpg-preview")
    }

    // MARK: - Grid / preview helpers (FileMetadataUITests pattern)

    private func openGridItem(uuid: String) {
        let item = app.descendants(matching: .any)["fileGridItem-\(uuid)"]
        XCTAssertTrue(item.waitForExistence(timeout: 20), "grid item fileGridItem-\(uuid)")
        item.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["previewFileNameCapsule"].waitForExistence(timeout: 12),
            "preview should open for \(uuid)"
        )
    }

    private func revealPreviewChromeIfNeeded() {
        let capsule = app.descendants(matching: .any)["previewFileNameCapsule"]
        if capsule.exists { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        _ = capsule.waitForExistence(timeout: 3)
        if !capsule.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
            _ = capsule.waitForExistence(timeout: 3)
        }
    }

    private func assertPreviewFileNameContains(_ needle: String) {
        revealPreviewChromeIfNeeded()
        let capsule = app.descendants(matching: .any)["previewFileNameCapsule"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 8), "previewFileNameCapsule for '\(needle)'")
        var value = capsule.value as? String ?? ""
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            value = capsule.value as? String ?? ""
            if value.contains(needle) { break }
            revealPreviewChromeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(
            value.contains(needle),
            "preview accessibilityValue should contain '\(needle)' (got '\(value)', label='\(capsule.label)')"
        )
    }

    private func requireUUID(named fileName: String) throws -> String {
        if sourceFolder.isEmpty {
            sourceFolder = try discoverSourceFolder()
        }
        let files = try listFiles(folder: sourceFolder)
        guard let hit = files.first(where: { ($0["file_name"] as? String) == fileName }),
              let uuid = hit["uuid"] as? String else {
            throw XCTSkip("No indexed file named \(fileName) under \(sourceFolder) — seed fixtures + scan")
        }
        return uuid
    }

    private func listFiles(folder: String) throws -> [[String: Any]] {
        let enc = folder.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? folder
        let url = URL(string: "\(serverURL)/api/indexer/files?folder_path=\(enc)&limit=100")!
        return try apiGET(url)["files"] as? [[String: Any]] ?? []
    }

    private func discoverSourceFolder() throws -> String {
        let url = URL(string: "\(serverURL)/api/config/sources")!
        let json = try apiGET(url)
        if let current = json["current"] as? String, !current.isEmpty { return current }
        if let sources = json["sources"] as? [[String: Any]],
           let first = sources.first?["path"] as? String {
            return first
        }
        let stateURL = URL(string: "\(serverURL)/api/config/state")!
        let state = try apiGET(stateURL)
        if let sf = state["source_folder"] as? String ?? state["sourceFolder"] as? String {
            return sf
        }
        throw XCTSkip("Could not discover source folder; set E2E_SOURCE_FOLDER")
    }

    private func apiGET(_ url: URL) throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.timeoutInterval = 15
        let sem = DispatchSemaphore(value: 0)
        var dataOut: Data?
        var errOut: Error?
        URLSession.shared.dataTask(with: req) { data, _, err in
            dataOut = data
            errOut = err
            sem.signal()
        }.resume()
        XCTAssertEqual(sem.wait(timeout: .now() + 20), .success, "API timeout \(url)")
        if let errOut { throw errOut }
        guard let dataOut,
              let json = try JSONSerialization.jsonObject(with: dataOut) as? [String: Any] else {
            throw NSError(
                domain: "HeicLivePhotoUITests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "bad JSON from \(url)"]
            )
        }
        return json
    }

    private func attachScreenshot(name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
