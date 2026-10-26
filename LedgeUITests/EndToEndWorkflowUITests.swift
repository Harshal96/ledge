import XCTest

/// The fixture keeps this workflow deterministic in CI while still exercising
/// the same launch, recovery, and one-primary/two-secondary shelf surface.
final class EndToEndWorkflowUITests: XCTestCase {
    func testFixtureLaunchesIntoRecoverableShelf() {
        let app = XCUIApplication()
        app.launchArguments = ["-ledge-screen-fixture", "notched", "-ledge-hotkey-result", "registered"]
        app.launch()

        XCTAssertEqual(app.staticTexts["ui.recovery.status-menu"].label, "available")
        XCTAssertEqual(app.staticTexts["ui.shell.presentation"].label, "peek")
        XCTAssertTrue(app.staticTexts["ui.fixture.screen"].waitForExistence(timeout: 2))
        app.terminate()
    }
}
