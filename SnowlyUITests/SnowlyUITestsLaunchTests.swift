//
//  SnowlyUITestsLaunchTests.swift
//  SnowlyUITests
//

import XCTest

final class SnowlyUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui_testing", "-ui_testing_skip_onboarding"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunch_freshInstall() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui_testing"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Fresh Install Launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
