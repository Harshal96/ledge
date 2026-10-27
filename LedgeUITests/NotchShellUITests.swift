import XCTest

final class NotchShellUITests: XCTestCase {
    @MainActor func testFreshInstallShowsLibraryAndNoBuiltInFeatureControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ledge-onboarding-completed", "YES", "-ledge.recovery.menuIcon", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Make the notch yours."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Quick Capture"].exists)
        XCTAssertFalse(app.buttons["Audio Controls"].exists)
        XCTAssertFalse(app.buttons["Search Clipboard"].exists)
        XCTAssertTrue(app.buttons["Install a local app…"].exists)
    }
    @MainActor func testHotkeyOpensEmptyNotchWithoutFeaturePermissions() throws {
        let app = XCUIApplication(); app.launch()
        app.typeKey(.space, modifierFlags: [.command, .option])
        XCTAssertTrue(app.buttons["notch.install-apps"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.buttons["notch.install-apps"].exists)
    }
}
