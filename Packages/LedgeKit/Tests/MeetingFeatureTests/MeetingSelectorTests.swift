import Foundation
import Testing
@testable import MeetingFeature

@Test("Selector chooses the next joinable accepted meeting")
func selectsNextMeeting() {
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    let declined = Meeting.fixture(start: now.addingTimeInterval(60), participation: .declined)
    let allDay = Meeting.fixture(start: now.addingTimeInterval(120), isAllDay: true)
    let ended = Meeting.fixture(start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-1))
    let accepted = Meeting.fixture(start: now.addingTimeInterval(300), participation: .accepted)

    #expect(MeetingSelector().next(from: [declined, allDay, ended, accepted], now: now)?.id == accepted.id)
}

@Test("Selector excludes cancelled meetings and orders upcoming meetings")
func selectorExclusionsAndOrder() {
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    let later = Meeting.fixture(start: now.addingTimeInterval(360), participation: .accepted)
    let cancelled = Meeting.fixture(start: now.addingTimeInterval(60), status: .cancelled)
    let earlier = Meeting.fixture(start: now.addingTimeInterval(120), participation: .tentative)
    #expect(MeetingSelector().next(from: [later, cancelled, earlier], now: now)?.id == earlier.id)
}
