import Foundation
import LedgeDomain

public protocol WallClock: Sendable { func now() -> Date }
public struct SystemWallClock: WallClock {
    public init() {}
    public func now() -> Date { .now }
}

public actor ExpiryScheduler {
    private let repository: any ShelfRepository
    private let clock: any WallClock
    public init(repository: any ShelfRepository, clock: any WallClock = SystemWallClock()) { self.repository = repository; self.clock = clock }
    @discardableResult public func purgeNow() async throws -> PurgeReport { try await repository.purgeExpired(before: clock.now()) }
}
