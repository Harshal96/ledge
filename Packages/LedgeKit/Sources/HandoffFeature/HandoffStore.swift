import Foundation
import Observation
import LedgeDomain

@MainActor @Observable public final class HandoffStore {
    public private(set) var items: [ShelfItem] = []; public private(set) var errorMessage: String?
    private let service: HandoffService
    public init(service: HandoffService) { self.service = service }
    public func refresh() async { do { items = try await serviceItems() } catch { errorMessage = "Handoff unavailable" } }
    public func clearExpired() async { do { _ = try await service.cleanup(); await refresh() } catch { errorMessage = "Could not clear expired items" } }
    private func serviceItems() async throws -> [ShelfItem] { try await service.list() }
}
