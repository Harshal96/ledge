import Testing
@testable import MeetingFeature

@Test("Join parser rejects executable and credential-bearing URLs")
func rejectsDangerousJoinURLs() {
    let parser = JoinURLParser(knownHTTPSHosts: ["meet.google.com", "zoom.us"])
    #expect(parser.parse("javascript:alert(1)") == nil)
    #expect(parser.parse("https://user:password@example.com/meeting") == nil)
    #expect(parser.parse("Join https://meet.google.com/abc-defg-hij")?.requiresConfirmation == false)
    #expect(parser.parse("https://video.example.org/room")?.requiresConfirmation == true)
}

@Test("Event URL wins over location and notes")
func urlPrecedence() {
    let parser = JoinURLParser(knownHTTPSHosts: ["meet.google.com"])
    let meeting = Meeting.fixture(url: "https://meet.google.com/event-url", location: "https://bad.example/location", notes: "https://bad.example/notes")
    #expect(parser.joinURL(for: meeting)?.url.absoluteString == "https://meet.google.com/event-url")
}

@Test("Known host must be a hostname boundary")
func hostBoundary() {
    let parser = JoinURLParser(knownHTTPSHosts: ["zoom.us"])
    #expect(parser.parse("https://zoom.us.example.com/room")?.requiresConfirmation == true)
}
