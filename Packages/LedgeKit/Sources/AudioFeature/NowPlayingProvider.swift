import Foundation

public struct UnavailableNowPlayingProvider: NowPlayingProviding {
    public init() {}
    public func snapshots() -> AsyncStream<NowPlayingSnapshot> {
        AsyncStream { continuation in
            continuation.yield(.unavailable(reason: .noPublicCrossAppAPI))
            continuation.finish()
        }
    }
    public func perform(_ command: TransportCommand) async throws {
        throw NowPlayingError.unavailable(.noPublicCrossAppAPI)
    }
}
