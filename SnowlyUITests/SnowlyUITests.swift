//
//  SnowlyUITests.swift
//  SnowlyUITests
//

import XCTest

final class SnowlyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Onboarding

    @MainActor
    func testOnboardingFlow_forFreshInstall() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui_testing"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome to Snowly"].waitForExistence(timeout: 3))

        app.buttons["Plan First Run"].tap()
        XCTAssertTrue(app.staticTexts["Permissions"].waitForExistence(timeout: 3))

        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Ready for the Slopes"].waitForExistence(timeout: 3))
    }

    // MARK: - Tab Navigation

    @MainActor
    func testMainTabs_whenOnboardingSkipped() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui_testing", "-ui_testing_skip_onboarding"]
        app.launch()

        XCTAssertTrue(app.buttons["ui_start_tracking_button"].waitForExistence(timeout: 8))

        app.buttons["Tracks"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Tracks"].waitForExistence(timeout: 3))

        app.buttons["Gear"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Gear"].waitForExistence(timeout: 3))

        app.buttons["Ride"].tap()
        XCTAssertTrue(app.buttons["ui_start_tracking_button"].waitForExistence(timeout: 6))
    }

    // MARK: - Tracking Lifecycle

    @MainActor
    func testTrackingStartAndPause() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui_testing",
            "-ui_testing_skip_onboarding",
            "-ui_testing_fast_start",
        ]
        app.launch()

        let startButton = app.buttons["ui_start_tracking_button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8))
        startButton.tap()

        let pauseButton = app.buttons["pause_tracking_button"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 8))
        pauseButton.tap()

        XCTAssertTrue(app.buttons["resume_tracking_button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTrackingStartWithLongPressButton() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui_testing",
            "-ui_testing_skip_onboarding",
            "-ui_testing_fast_start",
        ]
        app.launch()

        let startButton = app.buttons["start_tracking_button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8))
        startButton.press(forDuration: 0.4)

        XCTAssertTrue(app.buttons["pause_tracking_button"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testTrackingStartPauseResume() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui_testing",
            "-ui_testing_skip_onboarding",
            "-ui_testing_fast_start",
        ]
        app.launch()

        let startButton = app.buttons["ui_start_tracking_button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8))
        startButton.tap()

        // Pause
        let pauseButton = app.buttons["pause_tracking_button"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 8))
        pauseButton.tap()

        // Resume
        let resumeButton = app.buttons["resume_tracking_button"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 5))
        resumeButton.tap()

        // Should be back to recording — pause button visible again
        XCTAssertTrue(app.buttons["pause_tracking_button"].waitForExistence(timeout: 5))
    }

    // MARK: - Settings Navigation

    @MainActor
    func testSettingsNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui_testing", "-ui_testing_skip_onboarding"]
        app.launch()

        app.buttons["Tracks"].tap()

        let profileButton = app.buttons["profile_button"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 5))
        profileButton.tap()

        XCTAssertTrue(app.navigationBars.staticTexts["Profile"].waitForExistence(timeout: 3))

        let settingsLink = app.buttons["profile_settings_link"]
        XCTAssertTrue(settingsLink.waitForExistence(timeout: 3))
        settingsLink.tap()

        XCTAssertTrue(app.navigationBars.staticTexts["Settings"].waitForExistence(timeout: 3))
    }

    // MARK: - Gear Tab

    @MainActor
    func testGearTabNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui_testing", "-ui_testing_skip_onboarding"]
        app.launch()

        app.buttons["Gear"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Gear"].waitForExistence(timeout: 3))
    }

    // MARK: - Performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-ui_testing", "-ui_testing_skip_onboarding"]
            app.launch()
        }
    }
}
