import Foundation

public protocol WallClock: Sendable {
    func now() -> Date
    func sleep(until deadline: Date) async throws
}

public protocol ExternalURLOpening: Sendable {
    func open(_ url: URL) async throws
}
