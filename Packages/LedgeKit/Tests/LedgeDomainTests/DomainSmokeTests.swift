import Foundation
import Testing
@testable import LedgeDomain

@Test("Shelf item defaults remain local and expiring")
func shelfItemDefaults() {
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    let draft = ShelfItemDraft.note("Ship the smallest useful slice", now: now)

    #expect(draft.kind == .note)
    #expect(draft.createdAt == now)
    #expect(draft.expiresAt == now.addingTimeInterval(30 * 86_400))
    #expect(draft.source == nil)
}

@Test("External URLs fail closed at the shared boundary")
func externalURLPolicy() {
    let policy = ExternalURLPolicy(maximumUTF8Bytes: 8_192)

    #expect(policy.validate("https://example.com/runbook").isSuccess)
    #expect(policy.validate("https://user:secret@example.com").isFailure)
    #expect(policy.validate("javascript:alert(1)").isFailure)
    #expect(policy.validate("https://zoom.us.example.com/room").isSuccess)
}
