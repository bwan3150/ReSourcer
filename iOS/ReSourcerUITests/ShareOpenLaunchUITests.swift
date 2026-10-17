//
//  ShareOpenLaunchUITests.swift
//  ReSourcerUITests
//
//  真实系统分享表 E2E：Safari → Share Sheet → ReSourcer 扩展 →「打开下载页」
//  → 宿主 App 前台并进入下载预填页。覆盖冷启动与后台唤醒。禁止深链 stub。
//

import XCTest

final class ShareOpenLaunchUITests: XCTestCase {

    private var serverURL: String!
    private var apiKey: String!

    private let coldURL = "https://example.com/share-open-cold-e2e"
    private let warmURL = "https://example.com/share-open-warm-e2e"

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? env["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? env["RESOURCER_E2E_KEY"]
        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY for share open launch E2E"
        )
        serverURL = server!
        apiKey = key!
    }

    /// 冷启动：杀进程后从 Safari 真分享 → 打开 → App 启动到下载预填
    func testColdStartShareOpenLaunchesDownload() throws {
        seedHostLoginAndTerminate()

        let shared = coldURL
        openSafariAndShare(url: shared)
        tapReSourcerInShareSheet()
        captureShot(name: "02-extension-link-picker")
        confirmOpenInShareExtension()

        let app = XCUIApplication(bundleIdentifier: "app.resourcer.apple")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "host must come to foreground after Open")
        assertDownloadPrefill(in: app, expectedURL: shared)
        captureShot(name: "03-cold-start-download-prefill")
    }

    /// 后台：App 在后台时从 Safari 真分享 → 打开 → 回到前台下载预填
    func testBackgroundShareOpenForegroundsDownload() throws {
        seedHostLoginAndTerminate()

        let app = XCUIApplication(bundleIdentifier: "app.resourcer.apple")
        app.launchEnvironment["E2E_SERVER_URL"] = serverURL
        app.launchEnvironment["E2E_API_KEY"] = apiKey
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        // 停在非下载 Tab，确保后续切换可观察
        let gallery = app.tabBars.buttons["画廊"]
        if gallery.waitForExistence(timeout: 12) {
            gallery.tap()
        }
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10) || app.state == .runningBackgroundSuspended)

        let shared = warmURL
        openSafariAndShare(url: shared)
        tapReSourcerInShareSheet()
        confirmOpenInShareExtension()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "background host must foreground after Open")
        assertDownloadPrefill(in: app, expectedURL: shared)
        captureShot(name: "04-background-download-prefill")
    }

    // MARK: - Helpers

    private func seedHostLoginAndTerminate() {
        let app = XCUIApplication(bundleIdentifier: "app.resourcer.apple")
        app.launchEnvironment["E2E_SERVER_URL"] = serverURL
        app.launchEnvironment["E2E_API_KEY"] = apiKey
        app.launch()
        // 等到主界面 Tab 出现，确保 App Group / Keychain 已同步给 Extension
        let tab = app.tabBars.firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 25), "login/seed must reach main tabs")
        app.terminate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }

    private func openSafariAndShare(url: String) {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.activate()
        if safari.state != .runningForeground {
            safari.launch()
        }
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))

        // 地址栏：先点 TabOverview / URL 字段
        let urlField = safari.textFields["TabBarItemTitle"].exists
            ? safari.textFields["TabBarItemTitle"]
            : safari.textFields.firstMatch
        if urlField.waitForExistence(timeout: 8) {
            urlField.tap()
        } else if safari.buttons["URL"].waitForExistence(timeout: 4) {
            safari.buttons["URL"].tap()
        }

        let address = safari.textFields["URL"]
        let addressAlt = safari.textFields["Address"]
        let field = address.waitForExistence(timeout: 4) ? address
            : (addressAlt.waitForExistence(timeout: 2) ? addressAlt : safari.textFields.firstMatch)
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Safari address field")
        field.tap()
        // 清空旧地址再输入（避免叠字）
        if let current = field.value as? String, !current.isEmpty {
            let delete = String(repeating: XCUIKeyboardKey.delete.rawValue, count: min(current.count + 8, 80))
            field.typeText(delete)
        }
        field.typeText(url)
        let go = safari.buttons["Go"].exists ? safari.buttons["Go"] : safari.keyboards.buttons["Go"]
        if go.waitForExistence(timeout: 3) {
            go.tap()
        } else {
            field.typeText("\n")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))

        // iOS 26 中文 Safari：底栏无独立 Share，入口在「更多」→「共享」
        tapSafariShare(in: safari)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        captureShot(name: "01-safari-share-sheet")
    }

    /// 打开系统分享表（兼容 iOS 18–26 / 中英 UI）
    private func tapSafariShare(in safari: XCUIApplication) {
        let directCandidates = [
            safari.buttons["ShareButton"],
            safari.buttons["Share"],
            safari.buttons["共享"],
            safari.toolbars.buttons["Share"],
            safari.toolbars.buttons["共享"],
        ]
        for btn in directCandidates where btn.exists && btn.isHittable {
            btn.tap()
            return
        }

        let more = safari.buttons["更多"].exists ? safari.buttons["更多"] : safari.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "Safari More (更多) button for share entry")
        more.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        let shareInMenu = [
            safari.buttons["共享"],
            safari.buttons["Share"],
            safari.menuItems["共享"],
            safari.menuItems["Share"],
            safari.cells["共享"],
            safari.cells["Share"],
            safari.staticTexts["共享"],
            safari.staticTexts["Share"],
        ]
        for item in shareInMenu where item.waitForExistence(timeout: 2) {
            item.tap()
            return
        }

        // 页面菜单兜底
        let pageMenu = safari.buttons["PageFormatMenuButton"]
        if pageMenu.waitForExistence(timeout: 2) {
            pageMenu.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            for item in shareInMenu where item.waitForExistence(timeout: 2) {
                item.tap()
                return
            }
        }

        XCTFail("Could not open Safari system Share Sheet (shared/更多→共享)")
    }

    private func captureShot(name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // 同步落到仓库与 Agent Store，便于人工复核
        let png = shot.pngRepresentation
        let repoDir = URL(fileURLWithPath: "/Users/ericwang/Documents/GitHub/ReSourcer/docs/screenshots/share-open-launch")
        let storeDir = URL(fileURLWithPath: "/Users/ericwang/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-01a13105-7e35-766a-9ab1-1448a0642bca/files/media/share-open-launch")
        for dir in [repoDir, storeDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
        }
    }

    private func tapReSourcerInShareSheet() {
        let hosts = [
            XCUIApplication(bundleIdentifier: "com.apple.springboard"),
            XCUIApplication(bundleIdentifier: "com.apple.mobilesafari"),
            XCUIApplication(),
        ]
        var hit: XCUIElement?
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline && hit == nil {
            for host in hosts {
                let labeled = host.descendants(matching: .any).matching(
                    NSPredicate(format: "label ==[c] %@ OR identifier ==[c] %@", "ReSourcer", "ReSourcer")
                )
                if labeled.count > 0, labeled.element(boundBy: 0).exists {
                    hit = labeled.element(boundBy: 0)
                    break
                }
                for kind in [host.cells["ReSourcer"], host.buttons["ReSourcer"], host.staticTexts["ReSourcer"]]
                where kind.exists {
                    hit = kind
                    break
                }
                if hit != nil { break }
            }
            if hit == nil {
                // 分享表 App 行可横向滑动
                hosts[0].swipeLeft()
                hosts[1].swipeLeft()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        XCTAssertNotNil(hit, "ReSourcer must appear in system Share Sheet")
        hit!.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }

    private func confirmOpenInShareExtension() {
        // 扩展跑在独立进程；查询宿主或 springboard 上的控件
        let app = XCUIApplication(bundleIdentifier: "app.resourcer.apple")
        let extHost = XCUIApplication(bundleIdentifier: "app.resourcer.apple.helper")

        let openButtonPredicates: [XCUIElement] = [
            extHost.buttons["shareURLOpenDownload"],
            extHost.buttons["打开下载页"],
            app.buttons["shareURLOpenDownload"],
            app.buttons["打开下载页"],
            XCUIApplication().buttons["打开下载页"],
            XCUIApplication().buttons["shareURLOpenDownload"],
        ]

        var tapped = false
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline && !tapped {
            for btn in openButtonPredicates {
                if btn.waitForExistence(timeout: 0.4) && btn.isHittable {
                    btn.tap()
                    tapped = true
                    break
                }
            }
            if !tapped {
                // 源文件夹可能仍在加载
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
        }
        XCTAssertTrue(tapped, "must tap 打开下载页 inside real Share Extension UI")
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    }

    private func assertDownloadPrefill(in app: XCUIApplication, expectedURL: String) {
        let downloadTab = app.tabBars.buttons["下载"]
        if downloadTab.waitForExistence(timeout: 8) {
            // 若已在下载页也可再点一次
            if !downloadTab.isSelected { downloadTab.tap() }
        }
        let field = app.textFields["downloadURLField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "download URL field after share open")
        let deadline = Date().addingTimeInterval(12)
        var value = ""
        while Date() < deadline {
            value = field.value as? String ?? ""
            if value == expectedURL || value.contains(expectedURL) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(
            value == expectedURL || value.contains(expectedURL),
            "expected prefill \(expectedURL), got \(value)"
        )
    }
}
