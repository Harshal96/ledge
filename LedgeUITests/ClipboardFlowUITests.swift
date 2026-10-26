import XCTest

final class ClipboardFlowUITests: XCTestCase {
    func testClipboardFixtureContract() {
        let app = XCUIApplication(); app.launchArguments = ["-ledge-ui-fixture", "clipboard"]
        app.launch(); XCTAssertEqual(app.staticTexts["ui.clipboard.fixture"].label, "clipboard"); app.terminate()
    }
}
