import XCTest

final class MeetingCardUITests: XCTestCase {
    func testMeetingFixtureContract() {
        let app = XCUIApplication(); app.launchArguments = ["-ledge-ui-fixture", "meeting-card", "-ledge-meeting-action", "join"]; app.launch()
        XCTAssertEqual(app.staticTexts["ui.meeting.fixture"].label, "meeting-card"); XCTAssertEqual(app.staticTexts["ui.meeting.action"].label, "join"); app.terminate()
    }
}
