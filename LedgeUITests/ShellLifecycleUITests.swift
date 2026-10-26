import XCTest

final class ShellLifecycleUITests: XCTestCase {
    func testLaunchesAcrossScreenFixturesWithoutRequestingAccessibility() {
        for fixture in ["notched", "notchless", "secondary-menu-bar", "negative-coordinate", "mirrored", "disconnected", "full-screen"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ledge-screen-fixture", fixture, "-ledge-hotkey-result", "registered"]
            app.launch()
            XCTAssertEqual(app.staticTexts["ui.fixture.screen"].label, fixture)
            XCTAssertEqual(app.staticTexts["ui.recovery.status-menu"].label, "available")
            XCTAssertEqual(app.staticTexts["ui.shell.presentation"].label, ["full-screen", "disconnected"].contains(fixture) ? "hidden" : "peek")
            let expectedGeometry = switch fixture {
            case "notched": "x=0;top=37"
            case "negative-coordinate": "x=-1920;top=0"
            case "disconnected": "disconnected"
            default: "x=0;top=0"
            }
            XCTAssertEqual(app.staticTexts["ui.fixture.geometry"].label, expectedGeometry)
            app.terminate()
        }
    }

    func testEscapeDismissalFixtureLaunchesWithoutActivationFailure() {
        let app = XCUIApplication()
        app.launchArguments = ["-ledge-screen-fixture", "notched", "-ledge-shell-action", "escape"]
        app.launch()
        XCTAssertEqual(app.staticTexts["ui.fixture.action"].label, "escape")
        XCTAssertEqual(app.staticTexts["ui.shell.presentation"].label, "hidden")
        app.terminate()
    }
}
