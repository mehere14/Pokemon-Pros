//
//  BattleCardDexUITestsLaunchTests.swift
//  BattleCardDexUITests
//
//  Created by Mihir Panchal on 2026-08-31.
//

import XCTest

final class BattleCardDexUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BATTLE_CARD_DEX_USE_PREVIEW"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["Choose Your Battler"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Search and filter"].exists)

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
