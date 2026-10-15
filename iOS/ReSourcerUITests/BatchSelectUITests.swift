//
//  BatchSelectUITests.swift
//  ReSourcerUITests
//
//  Gallery 批量选择 / 批量移动 / 批量删除 E2E。
//  需要可用的后端（本机或局域网）并注入：
//    E2E_SERVER_URL=http://127.0.0.1:1234
//    E2E_API_KEY=<key>
//  以及测试源目录里至少 2 个已索引文件。
//
//  运行（macOS + Xcode）：
//    cd iOS && bash scripts/run-ui-tests.sh
//

import XCTest

final class BatchSelectUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        let env = ProcessInfo.processInfo.environment
        let server = env["E2E_SERVER_URL"] ?? ProcessInfo.processInfo.environment["RESOURCER_E2E_SERVER"]
        let key = env["E2E_API_KEY"] ?? ProcessInfo.processInfo.environment["RESOURCER_E2E_KEY"]

        // CI / Mac worker 未注入服务器时跳过，避免假红
        try XCTSkipIf(
            server == nil || server?.isEmpty == true || key == nil || key?.isEmpty == true,
            "Set E2E_SERVER_URL and E2E_API_KEY to run iOS batch UI E2E against a live server"
        )

        app.launchEnvironment["E2E_SERVER_URL"] = server!
        app.launchEnvironment["E2E_API_KEY"] = key!
        app.launch()
    }

    func testEnterBatchSelectModeShowsActionBar() throws {
        let toggle = app.buttons["batchSelectToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), "batch select toggle should appear on Gallery")
        toggle.tap()

        let bar = app.otherElements["batchActionBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "batch action bar should appear")
        XCTAssertTrue(app.buttons["batchMoveButton"].exists)
        XCTAssertTrue(app.buttons["batchDeleteButton"].exists)
        XCTAssertTrue(app.buttons["batchCancelButton"].exists)

        app.buttons["batchCancelButton"].tap()
        XCTAssertFalse(bar.waitForExistence(timeout: 2))
    }

    func testSelectAllEnablesBulkActions() throws {
        let toggle = app.buttons["batchSelectToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        toggle.tap()

        let selectAll = app.buttons["batchSelectAll"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        selectAll.tap()

        let move = app.buttons["batchMoveButton"]
        XCTAssertTrue(move.isEnabled, "move should enable after selecting files")
        let deleteBtn = app.buttons["batchDeleteButton"]
        XCTAssertTrue(deleteBtn.isEnabled, "delete should enable after selecting files")
    }

    func testBulkDeleteConfirmFlow() throws {
        let toggle = app.buttons["batchSelectToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        toggle.tap()
        app.buttons["batchSelectAll"].tap()
        app.buttons["batchDeleteButton"].tap()

        // GlassConfirmManager presents a destructive confirm
        let confirm = app.buttons["删除"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "delete confirm should appear")
        // Cancel to avoid mutating shared fixture data unless E2E_ALLOW_MUTATION=1
        if ProcessInfo.processInfo.environment["E2E_ALLOW_MUTATION"] == "1" {
            confirm.tap()
        } else {
            let cancel = app.buttons["取消"].firstMatch
            if cancel.exists { cancel.tap() }
        }
    }
}
