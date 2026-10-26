import XCTest

final class ScreenshotCaptureUITests: XCTestCase {
    func testScreenshotFixtureContract() {
        let app = XCUIApplication()
        app.launchArguments = ["-ledge-shell-action", "screenshot"]
        app.launch()
        XCTAssertEqual(app.staticTexts["ui.fixture.action"].label, "screenshot")
        app.terminate()
    }
}
