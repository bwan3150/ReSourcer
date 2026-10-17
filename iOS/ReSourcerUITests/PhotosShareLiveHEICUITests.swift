//
//  PhotosShareLiveHEICUITests.swift
//  ReSourcerUITests
//
//  真从系统相册 Photos → Share Sheet → ReSourcer，上传 HEIC 实况并校验服务端格式。
//  前置：模拟器相册已用 simctl addmedia 导入 IMG_LIVE.HEIC + IMG_LIVE.MOV（同 Content Identifier）。
//  环境：E2E_SERVER_URL / E2E_API_KEY / E2E_SOURCE_FOLDER / E2E_SCREENSHOT_DIR
//

import XCTest

@MainActor
final class PhotosShareLiveHEICUITests: XCTestCase {

    func testPhotosShareLiveHEICUploadsPairedHEICAndMOV() throws {
        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]
        let source = env["E2E_SOURCE_FOLDER"] ?? env["RESOURCER_E2E_SOURCE"] ?? ""
        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY"
        )
        let serverURL = server!
        let apiKey = key!

        // 先确保主 App 已登录（Share Extension 读 App Group / 已存凭证）
        let app = XCUIApplication()
        app.launchEnvironment["E2E_SERVER_URL"] = serverURL
        app.launchEnvironment["E2E_API_KEY"] = apiKey
        if !source.isEmpty {
            app.launchEnvironment["E2E_SOURCE_FOLDER"] = source
        }
        app.launchEnvironment["E2E_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        // 等进到主页
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 15)
        saveShot(app: app, name: "share-photos-01-app-ready")
        app.terminate()

        let before = try listHEICNames(serverURL: serverURL, apiKey: apiKey, folder: source)

        // Photos
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        photos.launch()
        XCTAssertTrue(photos.wait(for: .runningForeground, timeout: 15))

        // 权限
        let spring = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["继续", "允许访问所有照片", "Allow Access to All Photos", "OK", "允许"] {
            let b = spring.buttons[label].firstMatch
            if b.waitForExistence(timeout: 2) { b.tap() }
            let b2 = photos.buttons[label].firstMatch
            if b2.waitForExistence(timeout: 1) { b2.tap() }
        }
        saveShot(app: photos, name: "share-photos-02-library")

        // 打开第一张（已 addmedia 的实况应在库中）
        let image = photos.images.firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 12), "Photos library should have images")
        image.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        saveShot(app: photos, name: "share-photos-03-opened")

        // Share 按钮
        let shareCandidates = [
            photos.buttons["Share"],
            photos.buttons["共享"],
            photos.buttons["分享"],
            photos.buttons["square.and.arrow.up"],
            photos.descendants(matching: .any)["Share"],
            photos.descendants(matching: .any)["共享"],
        ]
        var shared = false
        for btn in shareCandidates {
            if btn.waitForExistence(timeout: 3), btn.isHittable {
                btn.tap()
                shared = true
                break
            }
        }
        if !shared {
            // 轻点屏幕唤出 chrome 再试
            photos.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            for btn in shareCandidates {
                if btn.waitForExistence(timeout: 2), btn.isHittable {
                    btn.tap()
                    shared = true
                    break
                }
            }
        }
        XCTAssertTrue(shared, "Could not open Photos share sheet")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        saveShot(app: photos, name: "share-photos-04-share-sheet")

        // 点 ReSourcer（可能在「更多」里）
        let hosts = [photos, spring, XCUIApplication()]
        var tappedExt = false
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline && !tappedExt {
            for host in hosts {
                let cell = host.descendants(matching: .any).matching(
                    NSPredicate(format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", "ReSourcer", "ReSourcer")
                ).firstMatch
                if cell.exists, cell.isHittable {
                    cell.tap()
                    tappedExt = true
                    break
                }
            }
            if tappedExt { break }
            // 滑到更多 App
            let collection = photos.collectionViews.firstMatch
            if collection.exists {
                collection.swipeLeft()
            }
            let more = photos.buttons["More"].firstMatch
            let moreZH = photos.buttons["更多"].firstMatch
            if more.exists { more.tap() }
            if moreZH.exists { moreZH.tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        XCTAssertTrue(tappedExt, "ReSourcer not found in Share Sheet — enable Share Extension in More")
        RunLoop.current.run(until: Date().addingTimeInterval(3.0))
        saveShot(app: photos, name: "share-photos-05-extension")

        // Extension 内点上传/完成（中英文）
        let extApp = XCUIApplication(bundleIdentifier: "app.resourcer.apple.ShareExtension")
        let uploadLabels = ["上传", "Upload", "开始上传", "发送", "Send", "完成", "Done"]
        for _ in 0..<15 {
            for label in uploadLabels {
                let b = extApp.buttons[label].firstMatch
                if b.exists, b.isHittable {
                    b.tap()
                    break
                }
                let b2 = photos.buttons[label].firstMatch
                if b2.exists, b2.isHittable {
                    b2.tap()
                    break
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            saveShot(app: photos, name: "share-photos-06-uploading")
        }

        // 轮询服务端：新增 HEIC，且魔数为 heic，并有配对 MOV
        var foundHEIC: String?
        var foundMOV: String?
        let pollDeadline = Date().addingTimeInterval(60)
        while Date() < pollDeadline {
            let files = try listFiles(serverURL: serverURL, apiKey: apiKey, folder: source)
            for f in files {
                let name = (f["file_name"] as? String) ?? ""
                if before.contains(name) { continue }
                let ext = (name as NSString).pathExtension.lowercased()
                if ext == "heic" || ext == "heif" {
                    foundHEIC = name
                    let stem = (name as NSString).deletingPathExtension
                    if let mov = files.first(where: {
                        let n = ($0["file_name"] as? String) ?? ""
                        return n.lowercased() == "\(stem.lowercased()).mov"
                    }) {
                        foundMOV = mov["file_name"] as? String
                    }
                    // 或 live_video_path
                    if f["live_video_path"] != nil || f["live_video_uuid"] != nil {
                        foundMOV = foundMOV ?? (f["live_video_path"] as? String) ?? "paired"
                    }
                }
            }
            if foundHEIC != nil { break }
            RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        }

        XCTAssertNotNil(foundHEIC, "Server should receive a new HEIC from Photos share")
        let heicName = foundHEIC!
        // 校验魔数
        let magic = try fetchMagic(serverURL: serverURL, apiKey: apiKey, folder: source, fileName: heicName)
        XCTAssertTrue(
            magic.contains("heic") || magic.contains("mif1") || magic.contains("heif") || magic.contains("msf1"),
            "Stored file must remain HEIC family, got magic=\(magic) file=\(heicName)"
        )
        XCTAssertNotNil(
            foundMOV,
            "HEIC live share must include paired MOV (stem match or live_video_*); heic=\(heicName)"
        )
        saveShot(app: photos, name: "share-photos-07-server-ok")
    }

    // MARK: - Helpers

    private func listHEICNames(serverURL: String, apiKey: String, folder: String) throws -> Set<String> {
        let files = try listFiles(serverURL: serverURL, apiKey: apiKey, folder: folder)
        return Set(files.compactMap { $0["file_name"] as? String })
    }

    private func listFiles(serverURL: String, apiKey: String, folder: String) throws -> [[String: Any]] {
        var folderPath = folder
        if folderPath.isEmpty {
            folderPath = try discoverSource(serverURL: serverURL, apiKey: apiKey)
        }
        let enc = folderPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? folderPath
        let url = URL(string: "\(serverURL)/api/indexer/files?folder_path=\(enc)&limit=200")!
        let json = try apiGET(url, apiKey: apiKey)
        return json["files"] as? [[String: Any]] ?? []
    }

    private func discoverSource(serverURL: String, apiKey: String) throws -> String {
        let url = URL(string: "\(serverURL)/api/config/sources")!
        let json = try apiGET(url, apiKey: apiKey)
        if let current = json["current"] as? String, !current.isEmpty { return current }
        throw XCTSkip("No source folder")
    }

    private func fetchMagic(serverURL: String, apiKey: String, folder: String, fileName: String) throws -> String {
        let files = try listFiles(serverURL: serverURL, apiKey: apiKey, folder: folder)
        guard let hit = files.first(where: { ($0["file_name"] as? String) == fileName }),
              let uuid = hit["uuid"] as? String else {
            return "missing"
        }
        let url = URL(string: "\(serverURL)/api/preview/content/_?uuid=\(uuid)")!
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let sem = DispatchSemaphore(value: 0)
        var dataOut: Data?
        URLSession.shared.dataTask(with: req) { data, _, _ in
            dataOut = data
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 20)
        guard let data = dataOut, data.count >= 12 else { return "empty" }
        // ftyp brand at offset 8
        let brand = String(data: data.subdata(in: 8..<12), encoding: .ascii) ?? ""
        return brand.lowercased()
    }

    private func apiGET(_ url: URL, apiKey: String) throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let sem = DispatchSemaphore(value: 0)
        var dataOut: Data?
        var errOut: Error?
        URLSession.shared.dataTask(with: req) { data, _, err in
            dataOut = data
            errOut = err
            sem.signal()
        }.resume()
        XCTAssertEqual(sem.wait(timeout: .now() + 20), .success)
        if let errOut { throw errOut }
        guard let dataOut,
              let json = try JSONSerialization.jsonObject(with: dataOut) as? [String: Any] else {
            throw NSError(domain: "PhotosShare", code: 1)
        }
        return json
    }

    private func saveShot(app: XCUIApplication, name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
        let env = ProcessInfo.processInfo.environment
        let dirPath = env["E2E_SCREENSHOT_DIR"]
            ?? env["TEST_RUNNER_E2E_SCREENSHOT_DIR"]
            ?? NSTemporaryDirectory()
        let dir = URL(fileURLWithPath: dirPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
        _ = app // silence unused in some paths
    }
}
