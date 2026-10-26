import Foundation

public struct AudioActivityPolicy: Sendable {
    public let recentWindow: Duration
    public init(recentWindow: Duration = .seconds(60)) { self.recentWindow = recentWindow }
    public func isEligible(openedAt: ContinuousClock.Instant, now: ContinuousClock.Instant) -> Bool {
        guard now >= openedAt else { return false }
        return openedAt.duration(to: now) < recentWindow
    }
}
