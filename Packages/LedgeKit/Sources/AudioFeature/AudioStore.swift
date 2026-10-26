import Foundation
import LedgeDomain

public actor AudioStore {
    private let policy: AudioActivityPolicy
    private var openedAt: ContinuousClock.Instant?
    private var writeAt: ContinuousClock.Instant?

    public init(policy: AudioActivityPolicy = AudioActivityPolicy()) { self.policy = policy }
    public func openAudioControls(at instant: ContinuousClock.Instant = ContinuousClock().now) { openedAt = instant; writeAt = nil }
    public func beginWrite(at instant: ContinuousClock.Instant = ContinuousClock().now) { writeAt = instant }
    public func finishWrite() { writeAt = nil }
    public func candidate(now: ContinuousClock.Instant = ContinuousClock().now) -> ActionCandidate? {
        if let writeAt, now >= writeAt, writeAt.duration(to: now) < .seconds(2) {
            return ActionCandidate(id: FixedActionID.audioControls, feature: .audio, title: "Audio Controls", subtitle: "Confirming device change", urgency: .immediate, sensitivity: .public, command: .openAudioControls)
        }
        guard let openedAt, policy.isEligible(openedAt: openedAt, now: now) else { return nil }
        return ActionCandidate(id: FixedActionID.audioControls, feature: .audio, title: "Audio Controls", urgency: .available, sensitivity: .public, command: .openAudioControls)
    }
}
