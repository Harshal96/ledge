import XCTest

final class HandoffFlowUITests: XCTestCase {
    func testHandoffFixtureContract() {
        let app = XCUIApplication()
        app.launchArguments = ["-ledge-shell-action", "share"]
        app.launch()
        XCTAssertEqual(app.staticTexts["ui.fixture.action"].label, "share")
        app.terminate()
    }

    func testHandoffSafeModeFixtureContract() {
        let app = XCUIApplication()
        app.launchArguments = ["-ledge-presentation-safe", "YES"]
        app.launch()
        XCTAssertEqual(app.staticTexts["ui.presentation-safe"].label, "enabled")
        XCTAssertEqual(app.staticTexts["ui.shell.presentation"].label, "hidden")
        app.terminate()
    }
}
