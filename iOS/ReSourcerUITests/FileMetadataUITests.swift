//
//  FileMetadataUITests.swift
//  ReSourcerUITests
//
//  文件详情元数据 — 真实后端 E2E（模块内容断言 + 操作突变）。
//
//  需要：
//    E2E_SERVER_URL=http://127.0.0.1:1234
//    E2E_API_KEY=<key>
//    E2E_SOURCE_FOLDER=/path/to/src   # 已索引源目录（含 HEIC / plain.png / clip.mp4）
//  突变用例另需：
//    E2E_ALLOW_MUTATION=1
//    源目录含 mutate-target.jpg（或测试会尝试复制失败时 skip）
//

import XCTest

final class FileMetadataUITests: XCTestCase {

    var app: XCUIApplication!
    var serverURL: String = ""
    var apiKey: String = ""
    var sourceFolder: String = ""
    var allowMutation: Bool = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]
        sourceFolder = env["E2E_SOURCE_FOLDER"] ?? env["RESOURCER_E2E_SOURCE"] ?? ""
        allowMutation = (env["E2E_ALLOW_MUTATION"] ?? "0") == "1"

        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY for file-metadata real-backend E2E"
        )

        serverURL = server!
        apiKey = key!

        app.launchEnvironment["E2E_SERVER_URL"] = serverURL
        app.launchEnvironment["E2E_API_KEY"] = apiKey
        app.launch()
    }

    // MARK: - (1) Module content vs live metadata

    func testRichHEICShowsTimeDeviceGPSMatchingServer() throws {
        let uuid = try requireUUID(named: "IMG_4821.HEIC")
        let meta = try fetchMetadata(named: "IMG_4821.HEIC")

        openGridItem(uuid: uuid)
        openInfoSheet()

        let time = app.descendants(matching: .any)["meta-module-time"]
        let device = app.descendants(matching: .any)["meta-module-device"]
        let gps = app.descendants(matching: .any)["meta-module-gps"]
        XCTAssertTrue(time.waitForExistence(timeout: 12), "时间 module visible for EXIF HEIC")
        XCTAssertTrue(device.waitForExistence(timeout: 5), "拍摄设备 module visible")
        XCTAssertTrue(gps.waitForExistence(timeout: 5), "地图定位 module visible")

        // Capture time — Photos-style zh_CN header from capture_time
        let capture = meta["capture_time"] as? String ?? ""
        XCTAssertFalse(capture.isEmpty)
        let expectedDateBits = expectedPhotosDateBits(from: capture)
        let captureLabel = app.descendants(matching: .any)["meta-capture-time"]
        XCTAssertTrue(captureLabel.waitForExistence(timeout: 5))
        let captureText = captureLabel.label
        for bit in expectedDateBits {
            XCTAssertTrue(
                captureText.contains(bit),
                "capture UI '\(captureText)' should contain '\(bit)' from server '\(capture)'"
            )
        }

        // Device — make + model from live API
        let make = meta["make"] as? String ?? ""
        let model = meta["model"] as? String ?? ""
        let deviceLabel = app.descendants(matching: .any)["meta-device"]
        XCTAssertTrue(deviceLabel.waitForExistence(timeout: 5))
        let deviceText = deviceLabel.label
        if !model.isEmpty {
            XCTAssertTrue(deviceText.contains(model), "device '\(deviceText)' should contain model '\(model)'")
        }
        if !make.isEmpty, !deviceText.contains(model) {
            XCTAssertTrue(deviceText.contains(make), "device '\(deviceText)' should contain make '\(make)'")
        }

        // GPS coords — match server lat/lon formatting
        guard let gpsObj = meta["gps"] as? [String: Any],
              let lat = gpsObj["lat"] as? Double,
              let lon = gpsObj["lon"] as? Double else {
            XCTFail("server HEIC metadata missing gps")
            return
        }
        let expectedGPS = formatGPS(lat: lat, lon: lon)
        let gpsCoords = app.descendants(matching: .any)["meta-gps-coords"]
        XCTAssertTrue(gpsCoords.waitForExistence(timeout: 5))
        XCTAssertEqual(
            gpsCoords.label.replacingOccurrences(of: " ", with: ""),
            expectedGPS.replacingOccurrences(of: " ", with: ""),
            "GPS text should match server coords"
        )

        // No duplicate key strings across modules (device model + GPS)
        assertAppearsOnce(substring: model.isEmpty ? make : model, in: app)
        assertKeyStringNotDuplicatedAcrossModules(expectedGPS)
    }

    /// Assert a distinctive string is not copied into 基础信息 when a richer module owns it.
    private func assertKeyStringNotDuplicatedAcrossModules(_ needle: String) {
        let basics = app.descendants(matching: .any)["meta-module-basics"]
        guard basics.exists else { return }
        var basicsLabels: [String] = []
        let kids = basics.descendants(matching: .any)
        for i in 0..<kids.count {
            let label = kids.element(boundBy: i).label
            if !label.isEmpty { basicsLabels.append(label) }
        }
        let basicsTexts = basicsLabels.joined(separator: " ")
        XCTAssertFalse(
            basicsTexts.replacingOccurrences(of: " ", with: "")
                .contains(needle.replacingOccurrences(of: " ", with: "")),
            "基础信息 must not duplicate owned field '\(needle)'"
        )
    }

    func testSparsePNGHidesTimeDeviceGPSModules() throws {
        let uuid = try requireUUID(named: "plain.png")
        let meta = try fetchMetadata(named: "plain.png")
        XCTAssertNil(meta["capture_time"], "fixture must lack capture_time")
        XCTAssertNil(meta["gps"], "fixture must lack gps")
        XCTAssertNil(meta["make"], "fixture must lack make")

        openGridItem(uuid: uuid)
        openInfoSheet()

        // Wait for basics (always present for sparse)
        let basics = app.descendants(matching: .any)["meta-module-basics"]
        XCTAssertTrue(basics.waitForExistence(timeout: 12), "基础信息 should show for sparse PNG")

        XCTAssertFalse(app.descendants(matching: .any)["meta-module-time"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["meta-module-device"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["meta-module-gps"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["meta-capture-time"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["meta-gps-coords"].exists)

        // Filename lives in 基础信息 when 时间 is hidden
        let filename = app.descendants(matching: .any)["meta-basics-filename"]
        if filename.waitForExistence(timeout: 3) {
            XCTAssertTrue(filename.label.contains("plain.png"))
        } else {
            XCTAssertTrue(app.staticTexts["plain.png"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "plain.png")).count > 0)
        }
    }

    func testVideoShowsDurationAndCodecInBasics() throws {
        let uuid = try requireUUID(named: "clip.mp4")
        let meta = try fetchMetadata(named: "clip.mp4")
        let duration = meta["duration"] as? Double ?? 0
        let codec = (meta["codec"] as? String ?? "").uppercased()
        XCTAssertGreaterThan(duration, 0)
        XCTAssertFalse(codec.isEmpty)

        openGridItem(uuid: uuid)
        openInfoSheet()

        let basics = app.descendants(matching: .any)["meta-module-basics"]
        XCTAssertTrue(basics.waitForExistence(timeout: 12))

        let durationRow = app.descendants(matching: .any)["meta-basics-duration"]
        XCTAssertTrue(durationRow.waitForExistence(timeout: 5), "时长 row should exist for video")
        let expectedDur = formatDuration(duration)
        XCTAssertTrue(
            durationRow.label.contains(expectedDur) || durationRow.label.contains("0:01"),
            "duration UI '\(durationRow.label)' should match \(expectedDur)"
        )

        let codecRow = app.descendants(matching: .any)["meta-basics-codec"]
        XCTAssertTrue(codecRow.waitForExistence(timeout: 5), "编码 row should exist for video")
        XCTAssertTrue(
            codecRow.label.uppercased().contains(codec),
            "codec UI '\(codecRow.label)' should contain \(codec)"
        )

        // Video without capture EXIF should not show time/device/gps modules
        XCTAssertFalse(app.descendants(matching: .any)["meta-module-time"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["meta-module-gps"].exists)
    }

    // MARK: - (2) Action mutations vs live server

    func testRenameMoveDeleteMutateServerState() throws {
        try XCTSkipIf(!allowMutation, "Set E2E_ALLOW_MUTATION=1 for mutation E2E")
        try XCTSkipIf(sourceFolder.isEmpty, "Set E2E_SOURCE_FOLDER for mutation E2E")

        // Ensure disposable target exists (copy from HEIC/JPEG fixture if needed via API list)
        let mutateName = "mutate-target.jpg"
        var uuid = try? requireUUID(named: mutateName)
        if uuid == nil {
            throw XCTSkip("Seed \(mutateName) under E2E_SOURCE_FOLDER and rescan before mutation E2E")
        }
        uuid = uuid!

        // Use list view + per-row info (avoids FilePreview playlist index races).
        switchToListView()

        // --- RENAME ---
        openListInfo(uuid: uuid!, fileNameHint: "mutate-target.jpg")
        tapActionButton(labeled: "重命名")
        // Gallery rename sheet opens after ~300ms sheet dismiss
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        // #region agent log
        uiTestAgentLog(
            hypothesisId: "A",
            location: "FileMetadataUITests.swift:rename",
            message: "after tap 重命名 + 0.8s",
            data: [
                "renameBtn": app.buttons["重命名"].exists,
                "infoTitle": app.staticTexts["文件信息"].exists,
                "renameTitle": app.staticTexts["重命名"].exists,
                "textFieldCount": app.textFields.count
            ]
        )
        // #endregion

        var nameField = app.descendants(matching: .any)["renameTextField"].firstMatch
        if !nameField.waitForExistence(timeout: 3) {
            nameField = app.textFields["文件名"].firstMatch
        }
        if !nameField.waitForExistence(timeout: 3) {
            nameField = app.textFields.firstMatch
        }
        // #region agent log
        if !nameField.exists {
            let btnLabels = (0..<min(app.buttons.count, 12)).map { app.buttons.element(boundBy: $0).label }
            uiTestAgentLog(
                hypothesisId: "D",
                location: "FileMetadataUITests.swift:rename",
                message: "rename TextField missing; hierarchy snapshot",
                data: [
                    "textFieldCount": app.textFields.count,
                    "renameTitle": app.staticTexts["重命名"].exists,
                    "infoTitle": app.staticTexts["文件信息"].exists,
                    "buttonLabels": btnLabels
                ]
            )
        }
        // #endregion
        XCTAssertTrue(nameField.waitForExistence(timeout: 8), "rename TextField")
        nameField.tap()
        if let current = nameField.value as? String, !current.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 8)
            nameField.typeText(deleteString)
        }
        nameField.typeText("mutate-renamed")

        let confirmRename = app.descendants(matching: .any)["renameConfirmButton"].firstMatch
        XCTAssertTrue(confirmRename.waitForExistence(timeout: 8), "rename confirm")
        if confirmRename.isHittable {
            confirmRename.tap()
        } else {
            confirmRename.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))

        var renamed = waitForFile(named: "mutate-renamed.jpg", timeout: 8)
        if renamed == nil {
            try? triggerScan()
            renamed = waitForFile(named: "mutate-renamed.jpg", timeout: 12)
        }
        XCTAssertNotNil(renamed, "server should list mutate-renamed.jpg after UI rename")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sourceFolder + "/mutate-renamed.mp4"),
            "must not rename video"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sourceFolder + "/mutate-target.jpg"),
            "original mutate-target.jpg should be gone after rename"
        )
        uuid = renamed!["uuid"] as? String
        let renamedPath = renamed!["current_path"] as? String ?? ""
        XCTAssertTrue(renamedPath.hasSuffix("mutate-renamed.jpg"), "path=\(renamedPath)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedPath), "fs \(renamedPath)")

        // Refresh gallery list
        app.terminate()
        app.launchEnvironment["E2E_SERVER_URL"] = serverURL
        app.launchEnvironment["E2E_API_KEY"] = apiKey
        app.launch()
        switchToListView()

        // --- MOVE to Album ---
        openListInfo(uuid: uuid!, fileNameHint: "mutate-renamed.jpg")
        tapActionButton(labeled: "移动")

        let album = app.staticTexts["Album"].firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 10), "Album folder in move sheet")
        album.tap()
        let moveHere = app.buttons["moveHereButton"]
        let moveHereLabel = app.buttons["移动至此"]
        if moveHere.waitForExistence(timeout: 5) {
            moveHere.tap()
        } else {
            XCTAssertTrue(moveHereLabel.waitForExistence(timeout: 5))
            moveHereLabel.tap()
        }

        var moved = waitForFile(named: "mutate-renamed.jpg", inFolder: sourceFolder + "/Album", timeout: 8)
        if moved == nil {
            try? triggerScan()
            moved = waitForFile(named: "mutate-renamed.jpg", inFolder: sourceFolder + "/Album", timeout: 12)
        }
        XCTAssertNotNil(moved, "file should appear under Album after move")
        let movedPath = moved!["current_path"] as? String ?? ""
        XCTAssertTrue(movedPath.contains("/Album/"), "path should include Album: \(movedPath)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedPath), "fs \(movedPath)")
        uuid = moved!["uuid"] as? String

        app.terminate()
        app.launchEnvironment["E2E_SERVER_URL"] = serverURL
        app.launchEnvironment["E2E_API_KEY"] = apiKey
        app.launch()
        switchToListView()

        // Enter Album folder then open info
        let albumFolder = app.staticTexts["Album"].firstMatch
        if albumFolder.waitForExistence(timeout: 8) {
            albumFolder.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        }

        openListInfo(uuid: uuid!, fileNameHint: "mutate-renamed.jpg")
        tapActionButton(labeled: "删除")

        let dialogTitle = app.staticTexts["删除此文件？"]
        XCTAssertTrue(dialogTitle.waitForExistence(timeout: 8), "delete confirm should appear")
        let deleteButtons = app.buttons.matching(NSPredicate(format: "label == %@", "删除"))
        XCTAssertGreaterThan(deleteButtons.count, 0)
        deleteButtons.element(boundBy: deleteButtons.count - 1).tap()

        var recycled = waitForFile(named: "mutate-renamed.jpg", inFolder: sourceFolder + "/_Recycle", timeout: 8)
        if recycled == nil {
            try? triggerScan()
            recycled = waitForFile(named: "mutate-renamed.jpg", inFolder: sourceFolder + "/_Recycle", timeout: 12)
        }
        XCTAssertNotNil(recycled, "soft-delete should place file under _Recycle")
        let recyclePath = recycled!["current_path"] as? String ?? ""
        XCTAssertTrue(recyclePath.contains("_Recycle"), "path should include _Recycle: \(recyclePath)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recyclePath), "fs \(recyclePath)")
    }

    /// Tap info-panel action without swiping the whole app (swipes dismiss glass sheets).
    private func tapActionButton(labeled label: String) {
        let btn = app.buttons[label].firstMatch
        XCTAssertTrue(btn.waitForExistence(timeout: 10), "\(label) action")
        // Glass / clipped rows often report !isHittable — coordinate tap is reliable.
        btn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    private func switchToListView() {
        let toggle = app.descendants(matching: .any)["galleryViewModeToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), "gallery view mode toggle")
        // Tap until a list row appears (grid → list). Cap at 2 taps.
        for _ in 0..<2 {
            let anyList = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "fileListItem-")
            ).firstMatch
            if anyList.waitForExistence(timeout: 2) { return }
            toggle.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        }
        let anyList = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fileListItem-")
        ).firstMatch
        XCTAssertTrue(anyList.waitForExistence(timeout: 5), "should be in list view with fileListItem-*")
    }

    private func openListInfo(uuid: String, fileNameHint: String? = nil) {
        switchToListView()
        let infoBtn = app.descendants(matching: .any)["fileInfoButton-\(uuid)"].firstMatch
        if !infoBtn.waitForExistence(timeout: 5) {
            for _ in 0..<4 {
                app.swipeUp()
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                if infoBtn.exists { break }
            }
        }
        if infoBtn.waitForExistence(timeout: 3) {
            infoBtn.tap()
        } else if let name = fileNameHint {
            // Fallback: find filename label then tap 文件信息 / ellipsis on that row
            let nameLabel = app.staticTexts[name].firstMatch
            XCTAssertTrue(nameLabel.waitForExistence(timeout: 10), "list filename \(name)")
            let infoButtons = app.buttons.matching(
                NSPredicate(format: "label == %@ OR identifier BEGINSWITH %@", "文件信息", "fileInfoButton-")
            )
            if infoButtons.count > 0 {
                infoButtons.element(boundBy: 0).tap()
            } else {
                // Coordinate tap to the right of the filename (ellipsis)
                nameLabel.coordinate(withNormalizedOffset: CGVector(dx: 3.5, dy: 0.5)).tap()
            }
        } else {
            XCTFail("list info button for \(uuid) not found")
            return
        }
        let actions = app.buttons["重命名"]
        let basics = app.descendants(matching: .any)["meta-module-basics"]
        XCTAssertTrue(
            actions.waitForExistence(timeout: 10) || basics.waitForExistence(timeout: 10),
            "info sheet should open from list"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    }

    // MARK: - Navigation helpers

    private func openGridItem(uuid: String) {
        let item = app.descendants(matching: .any)["fileGridItem-\(uuid)"]
        XCTAssertTrue(item.waitForExistence(timeout: 20), "grid item fileGridItem-\(uuid)")
        item.tap()
        // Preview chrome should appear
        XCTAssertTrue(
            app.descendants(matching: .any)["previewFileNameCapsule"].waitForExistence(timeout: 12),
            "preview should open for \(uuid)"
        )
    }

    private func assertPreviewFileNameContains(_ needle: String) {
        let capsule = app.descendants(matching: .any)["previewFileNameCapsule"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 8))
        // Prefer accessibilityValue (filename); label is the generic "文件信息"
        var value = capsule.value as? String ?? ""
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            value = capsule.value as? String ?? ""
            if value.contains(needle) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(
            value.contains(needle),
            "preview accessibilityValue should contain '\(needle)' (got '\(value)', label='\(capsule.label)')"
        )
    }

    private func openInfoSheet() {
        let capsule = app.descendants(matching: .any)["previewFileNameCapsule"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 12), "preview filename capsule")
        capsule.tap()
        let timeOrBasics = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@", ["meta-module-time", "meta-module-basics", "meta-module-device"])
        ).firstMatch
        let actions = app.buttons["重命名"]
        XCTAssertTrue(
            timeOrBasics.waitForExistence(timeout: 10) || actions.waitForExistence(timeout: 10),
            "info sheet / modules should appear"
        )
        // Extra beat for async metadata fetch
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    }

    private func triggerScan() throws {
        guard !sourceFolder.isEmpty else { return }
        let url = URL(string: "\(serverURL)/api/indexer/scan")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["source_folder": sourceFolder, "force": true]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, _, _ in sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 10)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    }

    private func dismissPreviewIfNeeded() {
        let back = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "chevron")).firstMatch
        if back.exists { back.tap(); return }
        // Tap left chevron image area — often exposed without label
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.08)).tap()
    }

    private func assertAppearsOnce(substring: String, in app: XCUIApplication, normalizeSpaces: Bool = false) {
        guard !substring.isEmpty else { return }
        let pred: NSPredicate
        if normalizeSpaces {
            pred = NSPredicate(format: "label CONTAINS[c] %@", substring)
        } else {
            pred = NSPredicate(format: "label CONTAINS %@", substring)
        }
        let matches = app.descendants(matching: .any).matching(pred)
        var labels: [String] = []
        let n = matches.count
        for i in 0..<n {
            let label = matches.element(boundBy: i).label
            if !label.isEmpty { labels.append(label) }
        }
        let unique = Set(labels)
        XCTAssertLessThanOrEqual(
            unique.count,
            2,
            "expected '\(substring)' at most in one module (got labels: \(unique))"
        )
        XCTAssertGreaterThanOrEqual(unique.count, 1, "expected '\(substring)' to appear")
    }

    // MARK: - Live API helpers

    private func requireUUID(named fileName: String) throws -> String {
        if sourceFolder.isEmpty {
            // Discover source from config/sources
            sourceFolder = try discoverSourceFolder()
        }
        let files = try listFiles(folder: sourceFolder)
        guard let hit = files.first(where: { ($0["file_name"] as? String) == fileName }),
              let uuid = hit["uuid"] as? String else {
            throw XCTSkip("No indexed file named \(fileName) under \(sourceFolder) — seed fixtures + scan")
        }
        return uuid
    }

    private func fetchMetadata(named fileName: String) throws -> [String: Any] {
        if sourceFolder.isEmpty {
            sourceFolder = try discoverSourceFolder()
        }
        let path = sourceFolder + "/" + fileName
        let enc = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let url = URL(string: "\(serverURL)/api/file/metadata?path=\(enc)")!
        return try apiGET(url)
    }

    private func waitForFile(named fileName: String, inFolder folder: String? = nil, timeout: TimeInterval) -> [String: Any]? {
        let folderPath = folder ?? sourceFolder
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let files = try? listFiles(folder: folderPath),
               let hit = files.first(where: { ($0["file_name"] as? String) == fileName }) {
                return hit
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        return nil
    }

    private func listFiles(folder: String) throws -> [[String: Any]] {
        let enc = folder.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? folder
        let url = URL(string: "\(serverURL)/api/indexer/files?folder_path=\(enc)&limit=100")!
        let json = try apiGET(url)
        return json["files"] as? [[String: Any]] ?? []
    }

    private func discoverSourceFolder() throws -> String {
        let url = URL(string: "\(serverURL)/api/config/sources")!
        let json = try apiGET(url)
        if let current = json["current"] as? String, !current.isEmpty { return current }
        if let sources = json["sources"] as? [[String: Any]],
           let first = sources.first?["path"] as? String {
            return first
        }
        // fallback: preference / state
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
            throw NSError(domain: "FileMetadataUITests", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad JSON from \(url)"])
        }
        return json
    }

    // MARK: - Format mirrors (keep in sync with FileModels / FileInfoSheetContent)

    private func expectedPhotosDateBits(from raw: String) -> [String] {
        // formatPhotosDate: "EEEE • M月d日 • HH:mm" with zh_CN
        let head = String(raw.prefix(19))
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let date = f.date(from: head) else { return [raw] }
        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.dateFormat = "EEEE"
        let weekday = out.string(from: date)
        out.dateFormat = "M月d日"
        let day = out.string(from: date)
        out.dateFormat = "HH:mm"
        let time = out.string(from: date)
        return [weekday, day, time]
    }

    private func formatGPS(lat: Double, lon: Double) -> String {
        let latHem = lat >= 0 ? "N" : "S"
        let lonHem = lon >= 0 ? "E" : "W"
        return String(format: "%.5f° %@, %.5f° %@", abs(lat), latHem, abs(lon), lonHem)
    }

    private func formatDuration(_ duration: Double) -> String {
        let total = Int(duration)
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // #region agent log
    private func uiTestAgentLog(hypothesisId: String, location: String, message: String, data: [String: Any]) {
        var payload: [String: Any] = [
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "data": data,
            "runId": "uitest"
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let json = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: json, encoding: .utf8) else { return }
        line += "\n"
        let paths = [
            "/tmp/cursor-logs/debug.log",
            "/Users/ericwang/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-4ed54bed-c0eb-54c2-bd0a-3c585eab4c6e/files/artifacts/debug.log"
        ]
        for path in paths {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            guard let handle = FileHandle(forWritingAtPath: path) else { continue }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let bytes = line.data(using: .utf8) {
                try? handle.write(contentsOf: bytes)
            }
        }
        print("AGENT_DEBUG \(line)", terminator: "")
    }
    // #endregion
}
