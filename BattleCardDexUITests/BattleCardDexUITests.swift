//
//  BattleCardDexUITests.swift
//  BattleCardDexUITests
//
//  Created by Mihir Panchal on 2026-08-31.
//

import XCTest

final class BattleCardDexUITests: XCTestCase {

    private static let liveCloudKitOptInKey = "BATTLE_CARD_DEX_RUN_LIVE_CLOUDKIT_TESTS"

    func testDebugCardEffectsLabOpensFromHome() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BATTLE_CARD_DEX_USE_PREVIEW"] = "1"
        app.launch()

        let cta = app.buttons["card-effects-lab-cta"]
        XCTAssertTrue(cta.waitForExistence(timeout: 10))
        cta.tap()
        XCTAssertTrue(app.descendants(matching: .any)["card-effects-lab"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Common / Uncommon"].exists)
        XCTAssertTrue(app.buttons["Effects Off"].exists)
        XCTAssertTrue(app.buttons["Reset"].exists)
        XCTAssertTrue(app.images["effect-artwork-loaded-Common / Uncommon"].waitForExistence(timeout: 15))
        let finishOn = XCTAttachment(screenshot: app.screenshot())
        finishOn.name = "Card finish enabled"
        finishOn.lifetime = .keepAlways
        add(finishOn)
        app.buttons["Effects Off"].tap()
        let finishOff = XCTAttachment(screenshot: app.screenshot())
        finishOff.name = "Card finish disabled"
        finishOff.lifetime = .keepAlways
        add(finishOff)
        app.buttons["Done"].tap()
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testSignedOutDevelopmentBuildReadsPublicCloudKitProbe() throws {
        try requireLiveCloudKitOptIn()
        let app = XCUIApplication()
        app.launchEnvironment["BATTLE_CARD_DEX_CLOUDKIT_PROBE"] = "read"
        app.launch()

        let status = app.staticTexts["cloudkit-development-probe-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 30))

        let completed = NSPredicate(format: "label != %@", "READ_PENDING")
        let expectation = XCTNSPredicateExpectation(predicate: completed, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 30), .completed)
        XCTAssertTrue(status.label.hasPrefix("READ_OK:"), "CloudKit probe result: \(status.label)")
        XCTAssertTrue(status.label.contains("CatalogManifest/catalog-manifest-v1"))
    }

    @MainActor
    func testDevelopmentAppCannotMutatePublicCatalogRecords() throws {
        try requireLiveCloudKitOptIn()
        let app = XCUIApplication()
        app.launchEnvironment["BATTLE_CARD_DEX_CLOUDKIT_PROBE"] = "mutation-denial"
        app.launch()

        let status = app.staticTexts["cloudkit-development-probe-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 30))

        let completed = NSPredicate(format: "label BEGINSWITH %@", "WRITE_DENIAL_")
        let expectation = XCTNSPredicateExpectation(predicate: completed, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 30), .completed)
        XCTAssertTrue(status.label.hasPrefix("WRITE_DENIAL_OK:"), "CloudKit probe result: \(status.label)")
        XCTAssertTrue(status.label.contains("create=denied("))
        XCTAssertTrue(status.label.contains("change=denied("))
        XCTAssertTrue(status.label.contains("delete=denied("))
    }

    private func requireLiveCloudKitOptIn() throws {
        guard ProcessInfo.processInfo.environment[Self.liveCloudKitOptInKey] == "1" else {
            throw XCTSkip("Live CloudKit verification requires explicit Development-only opt-in.")
        }
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testLauncherSearchAndDetailFlow() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BATTLE_CARD_DEX_USE_PREVIEW"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Choose Your Battler"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Creature 1"].exists)
        app.buttons["Search and filter"].tap()
        let search = app.textFields["Name or number"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("2")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Creature 2"].waitForExistence(timeout: 5))
        app.staticTexts["Creature 2"].tap()
        XCTAssertTrue(app.staticTexts["NO. 002"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Field Guide"].exists)
        XCTAssertTrue(app.buttons["Open Evolutions"].exists)
        XCTAssertTrue(app.buttons["Open Cards"].exists)
    }

    @MainActor
    func testPreviewDetailUsesVisibleCarouselControls() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BATTLE_CARD_DEX_USE_PREVIEW"] = "1"
        app.launch()

        app.buttons["Creature 1, number 1"].tap()
        XCTAssertTrue(app.buttons["Next creature"].waitForExistence(timeout: 5))
        let positionIndicator = app.descendants(matching: .any)["creature-position-indicator"]
        XCTAssertTrue(positionIndicator.exists)
        let initialPositionLabel = positionIndicator.label
        XCTAssertTrue(initialPositionLabel.hasPrefix("Creature 1 of "))
        app.buttons["Next creature"].tap()
        XCTAssertTrue(app.staticTexts["002"].waitForExistence(timeout: 5))
        XCTAssertEqual(positionIndicator.label, initialPositionLabel.replacingOccurrences(of: "Creature 1 of ", with: "Creature 2 of "))
        app.buttons["Previous creature"].tap()
        XCTAssertTrue(app.staticTexts["001"].waitForExistence(timeout: 5))

        app.buttons["Field Guide"].tap()
        XCTAssertTrue(app.navigationBars["Field Guide"].waitForExistence(timeout: 5))
        app.navigationBars["Field Guide"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Open Evolutions"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testIPadDetailIsFullScreenAndSupportsVerticalPanels() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BATTLE_CARD_DEX_USE_PREVIEW"] = "1"
        app.launch()

        app.buttons["Creature 1, number 1"].tap()
        XCTAssertTrue(app.staticTexts["NO. 001"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Back to all creatures"].isHittable)
        XCTAssertTrue(app.buttons["Field Guide"].isHittable)
        keepScreenshot(named: "iPad-full-screen-detail")

        let upperPoint = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
        let lowerPoint = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
        upperPoint.press(forDuration: 0.12, thenDragTo: lowerPoint)
        XCTAssertTrue(app.staticTexts["Creature 1 cards"].waitForExistence(timeout: 5))
        let cardsPanel = app.descendants(matching: .any)["related-cards-panel"]
        XCTAssertGreaterThan(cardsPanel.frame.height, app.frame.height * 0.90)
        keepScreenshot(named: "iPad-cards-panel")

        let firstCard = app.buttons["Creature 1 Card 1, Preview Set, 1"]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        firstCard.tap()
        let viewer = app.descendants(matching: .any)["interactive-card-viewer"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["MOVE TO CATCH THE LIGHT"].exists)
        let cardSurface = app.descendants(matching: .any)["interactive-card-surface"]
        XCTAssertTrue(cardSurface.exists)
        cardSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: cardSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8)))
        keepScreenshot(named: "iPad-interactive-card-viewer")
        app.buttons["Close card viewer"].tap()
        XCTAssertFalse(viewer.waitForExistence(timeout: 1))

        app.buttons["Close panel"].tap()
        XCTAssertFalse(app.staticTexts["Creature 1 cards"].waitForExistence(timeout: 1))

        lowerPoint.press(forDuration: 0.12, thenDragTo: upperPoint)
        XCTAssertTrue(app.staticTexts["Evolution path"].waitForExistence(timeout: 5))
        keepScreenshot(named: "iPad-evolution-panel")
        app.buttons["Close panel"].tap()
        XCTAssertFalse(app.staticTexts["Evolution path"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testLargestDynamicTypeKeepsLauncherControlsReachable() throws {
        let app = XCUIApplication()
        app.launchEnvironment["BATTLE_CARD_DEX_USE_PREVIEW"] = "1"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Choose Your Battler"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Search and filter"].isHittable)
        XCTAssertTrue(app.buttons["Surprise me"].isHittable)
    }

    @MainActor
    func testLightAndDarkAppearanceRenderLauncherAndDetail() throws {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["BATTLE_CARD_DEX_USE_PREVIEW"] = "1"
            app.launchArguments += ["-appearance", appearance]
            app.launch()

            XCTAssertTrue(app.staticTexts["Choose Your Battler"].waitForExistence(timeout: 10))
            keepScreenshot(named: "iPad-\(appearance)-launcher")

            app.buttons["Creature 1, number 1"].tap()
            XCTAssertTrue(app.staticTexts["NO. 001"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Field Guide"].isHittable)
            keepScreenshot(named: "iPad-\(appearance)-detail")

            app.terminate()
        }
    }
}
