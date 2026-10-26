import XCTest

final class AudioCardUITests: XCTestCase {
    func testAudioFixtureShowsCapabilityAwareControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-ledge-ui-fixture", "audio-card"]
        app.launch()
        XCTAssertEqual(app.staticTexts["ui.audio.fixture"].label, "audio-card")
        XCTAssertEqual(app.staticTexts["ui.audio.input-mute"].label, "unsupported")
        app.terminate()
    }
}
