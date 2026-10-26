import XCTest

final class OnboardingUITests: XCTestCase {
    func testFirstRunIsDismissibleWithoutPermissionPrompt() {
        let app = XCUIApplication()
        app.launchArguments = ["-ledge-reset-onboarding"]
        app.launch()

        XCTAssertTrue(app.waitForExistence(timeout: 2))
        XCTAssertFalse(app.alerts.staticTexts["Ledge would like to access your Calendar"].exists)
        XCTAssertFalse(app.alerts.staticTexts["Ledge would like to record this computer's screen"].exists)
        app.terminate()
    }
}
