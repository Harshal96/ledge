import Foundation
import Testing
@testable import MeetingFeature

@Test("Agenda preview is plain text and bounded")
func agendaPreviewIsBounded() {
    let redactor = PresentationRedactor()
    let agenda = "one\ntwo\nthree\nfour\nfive <b>six</b>"
    #expect(redactor.agendaPreview(agenda) == "one\ntwo\nthree\nfour")
    #expect(redactor.agendaPreview(String(repeating: "x", count: 1_100))?.count == 1_000)
}

@Test("Safe mode emits only countdown and join")
func safeModeRedactsMeetingContent() {
    let state = PresentationRedactor().renderState(
        meeting: Meeting.fixture(title: "Quarterly acquisition plan", notes: "Private agenda"),
        join: JoinURL(url: URL(string: "https://meet.google.com/abc-defg-hij")!, requiresConfirmation: false),
        now: Date(),
        safeMode: .manual
    )
    #expect(state.title == nil)
    #expect(state.agenda == nil)
    #expect(state.showsJoin == true)
    #expect(state.countdown != nil)
}

@Test("Manual safe mode has a bounded explicit reveal")
func manualSafeModeRevealExpires() async {
    let meeting = Meeting.fixture(title: "Quarterly acquisition plan", start: Date(timeIntervalSince1970: 1_786_320_100))
    let provider = FixedMeetingProvider(snapshot: MeetingSnapshot(access: .authorized, meetings: [meeting]))
    let store = await MainActor.run { MeetingStore(provider: provider) }
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    await store.refresh(now: now)
    await MainActor.run { store.setSafeMode(.manual); store.revealSensitiveContent(now: now) }
    #expect(await MainActor.run { store.state(now: now).title } == "Quarterly acquisition plan")
    #expect(await MainActor.run { store.state(now: now.addingTimeInterval(31)).title } == nil)
}

private actor FixedMeetingProvider: MeetingProviding {
    let snapshot: MeetingSnapshot
    init(snapshot: MeetingSnapshot) { self.snapshot = snapshot }
    func requestAccess() async -> MeetingAccess { snapshot.access }
    func refresh(now: Date) async -> MeetingSnapshot { snapshot }
}
