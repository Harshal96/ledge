import Foundation
import Testing
@testable import ShellFeature
import LedgeDomain

@Test("Joinable meeting outranks recent tray and capture")
func meetingWinsImmediateWindow() {
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    let candidates = [
        ActionCandidate.fixture(feature: .handoff, urgency: .available, dueAt: nil),
        ActionCandidate.fixture(feature: .capture, urgency: .available, dueAt: nil),
        ActionCandidate.fixture(feature: .meeting, urgency: .immediate, dueAt: now.addingTimeInterval(120))
    ]

    let result = ActionResolver().resolve(candidates, now: now, presentationSafe: false)

    #expect(result.primary?.feature == .meeting)
    #expect(result.secondary.count == 2)
    #expect(result.all.count == 3)
}

@Test("Presentation safe removes sensitive candidates before ranking")
func safeModeFiltersBeforeRanking() {
    let sensitive = ActionCandidate.fixture(feature: .clipboard, urgency: .immediate, sensitivity: .sensitive)
    let fallback = ActionCandidate.fixture(feature: .capture, urgency: .available, sensitivity: .public)

    let result = ActionResolver().resolve([sensitive, fallback], now: .distantPast, presentationSafe: true)

    #expect(result.primary?.id == fallback.id)
    #expect(!result.all.contains(where: { $0.id == sensitive.id }))
}

@Test("Disabled Quick Capture falls back to recovery Settings")
func disabledQuickCaptureDoesNotReappear() {
    let result = ActionResolver().resolve([], now: .distantPast, presentationSafe: false, enabledFeatures: [])

    #expect(result.primary?.id == FixedActionID.openSettings)
    #expect(result.primary?.feature == .recovery)
    #expect(result.all.contains(where: { $0.feature == .quickCapture }) == false)
}

@Test("Expired and session-dismissed actions are filtered")
func staleActionsAreNotReturned() {
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    let expired = ActionCandidate.fixture(feature: .capture, urgency: .immediate, expiresAt: now.addingTimeInterval(-1))
    let dismissed = ActionCandidate.fixture(feature: .handoff, urgency: .immediate)

    let result = ActionResolver().resolve(
        [expired, dismissed],
        now: now,
        presentationSafe: false,
        dismissedIDs: [dismissed.id]
    )

    #expect(result.primary?.id == FixedActionID.quickCapture)
}

@Test("Resolver returns no more than one primary and two secondaries")
func resolverCapsPresentation() {
    let candidates = FeatureID.allCases.map {
        ActionCandidate.fixture(feature: $0, urgency: .available)
    }

    let result = ActionResolver().resolve(candidates, now: .now, presentationSafe: false)

    #expect(result.primary != nil)
    #expect(result.secondary.count == 2)
    #expect(result.all.count == 3)
}
