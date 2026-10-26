import Foundation
import Testing
import LedgeDomain
@testable import AudioFeature

@Test("Opening Audio Controls emits a session-only available candidate")
func openingAudioControlsProducesCandidate() async {
    let store = AudioStore()
    let openedAt = ContinuousClock().now
    await store.openAudioControls(at: openedAt)

    let candidate = await store.candidate(now: openedAt.advanced(by: .seconds(30)))
    #expect(candidate?.feature == .audio)
    #expect(candidate?.urgency == .available)
    #expect(candidate?.command == .openAudioControls)
}

@Test("A confirmed-write window is immediate and expires after two seconds")
func writeCandidateHasShortWindow() async {
    let store = AudioStore()
    let startedAt = ContinuousClock().now
    await store.beginWrite(at: startedAt)

    #expect(await store.candidate(now: startedAt.advanced(by: .seconds(1)))?.urgency == .immediate)
    #expect(await store.candidate(now: startedAt.advanced(by: .seconds(2))) == nil)
}

@Test("Opening the general shelf does not create an audio candidate")
func noCandidateBeforeAudioRoute() async {
    let store = AudioStore()
    #expect(await store.candidate(now: .now) == nil)
}
