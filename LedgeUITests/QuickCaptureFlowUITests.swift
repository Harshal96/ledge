import XCTest

final class QuickCaptureFlowUITests: XCTestCase {
    func testQuickCaptureFixtureContract() {
        let app = XCUIApplication()
        app.launchArguments = ["-ledge-ui-fixture", "quick-capture", "-ledge-capture-action", "save-note"]
        app.launch()
        XCTAssertEqual(app.staticTexts["ui.capture.fixture"].label, "quick-capture")
        XCTAssertEqual(app.staticTexts["ui.capture.action"].label, "save-note")
        app.terminate()
    }
}
