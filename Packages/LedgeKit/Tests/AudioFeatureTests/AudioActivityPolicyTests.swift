import Foundation
import Testing
@testable import AudioFeature

@Test("Explicitly opened audio remains eligible for exactly sixty seconds")
func audioCandidateLifetime() {
    let openedAt = ContinuousClock().now
    let policy = AudioActivityPolicy(recentWindow: .seconds(60))

    #expect(policy.isEligible(openedAt: openedAt, now: openedAt.advanced(by: .seconds(59))))
    #expect(!policy.isEligible(openedAt: openedAt, now: openedAt.advanced(by: .seconds(60))))
}

@Test("Clock going backwards does not extend audio eligibility")
func backwardsClockIsNotEligible() {
    let openedAt = ContinuousClock().now
    let policy = AudioActivityPolicy(recentWindow: .seconds(60))

    #expect(!policy.isEligible(openedAt: openedAt, now: openedAt.advanced(by: .seconds(-1))))
}
