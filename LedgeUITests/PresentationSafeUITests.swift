import XCTest

final class PresentationSafeUITests: XCTestCase {
    func testPresentationSafeFixtureContract() {
        let app = XCUIApplication(); app.launchArguments = ["-ledge-ui-fixture", "presentation-safe", "-ledge-presentation-mode", "manual"]; app.launch()
        XCTAssertEqual(app.staticTexts["ui.presentation.fixture"].label, "presentation-safe"); XCTAssertEqual(app.staticTexts["ui.presentation.mode"].label, "manual"); app.terminate()
    }
}
