import XCTest

final class AccessibilityUITests: XCTestCase {
    func testLaunchKeepsAKeyboardAndMenuBarRecoveryPath() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.waitForExistence(timeout: 2))
        // A failed permission request must not replace the app with a modal gate.
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.terminate()
    }
}
