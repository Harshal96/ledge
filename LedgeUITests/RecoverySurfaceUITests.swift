import XCTest

final class RecoverySurfaceUITests: XCTestCase {
    func testHotkeyConflictStillLaunchesTheRecoverySurface() {
        let app = XCUIApplication()
        app.launchArguments = ["-ledge-hotkey-result", "conflict"]
        app.launch()
        XCTAssertEqual(app.staticTexts["ui.hotkey.result"].label, "conflict")
        XCTAssertEqual(app.staticTexts["ui.recovery.status-menu"].label, "available")
        XCTAssertEqual(app.staticTexts["ui.recovery.settings"].label, "opened")
        app.terminate()
    }

    func testPresentationSafeFixtureDoesNotRequireAccessibilityPermission() {
        let app = XCUIApplication()
        app.launchArguments = ["-ledge-presentation-safe", "YES"]
        app.launch()
        XCTAssertEqual(app.staticTexts["ui.presentation-safe"].label, "enabled")
        XCTAssertEqual(app.staticTexts["ui.shell.presentation"].label, "hidden")
        app.terminate()
    }
}
