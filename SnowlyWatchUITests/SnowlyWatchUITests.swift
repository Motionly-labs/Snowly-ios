//
//  SnowlyWatchUITests.swift
//  SnowlyWatchUITests
//

import XCTest

final class SnowlyWatchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        if app.state != .notRunning {
            app.terminate()
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func testInteractiveFlow_canStartPauseStopAndDismiss() throws {
        let app = launchApp(arguments: [
            "-watch_ui_testing",
            "-watch_ui_testing_interactive",
            "-watch_ui_testing_controls",
        ])

        let startButton = element(in: app, identifier: "watch_start_button")
        XCTAssertTrue(startButton.waitForExistence(timeout: 8))
        startButton.tap()

        let pauseResumeButton = element(in: app, identifier: "watch_pause_resume_button")
        XCTAssertTrue(pauseResumeButton.waitForExistence(timeout: 5))
        XCTAssertEqual(pauseResumeButton.value as? String, "active")

        pauseResumeButton.tap()
        XCTAssertEqual(pauseResumeButton.value as? String, "paused")

        pauseResumeButton.tap()
        XCTAssertEqual(pauseResumeButton.value as? String, "active")

        let stopButton = element(in: app, identifier: "watch_stop_button")
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5))
        stopButton.tap()

        let doneButton = element(in: app, identifier: "watch_summary_done_button")
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        XCTAssertTrue(element(in: app, identifier: "watch_start_button").waitForExistence(timeout: 8))
    }
}
