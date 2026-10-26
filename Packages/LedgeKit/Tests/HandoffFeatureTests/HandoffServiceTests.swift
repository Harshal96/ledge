import Foundation
import Testing
import LedgeDomain
@testable import HandoffFeature

@Test("Handoff default expiry is one day and cleanup is idempotent")
func handoffExpiryAndCleanup() async throws {
    let store = MemoryShelfRepository()
    let service = HandoffService(repository: store)
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    _ = try await service.importPayload(.text("private"), expiry: .oneDay, now: now)
    #expect((await store.inserted.first?.expiresAt) == now.addingTimeInterval(86_400))
    #expect(try await service.cleanup(now: now.addingTimeInterval(86_401)).deletedIDs.count == 1)
    #expect(try await service.cleanup(now: now.addingTimeInterval(86_402)).deletedIDs.isEmpty)
}

private actor MemoryShelfRepository: ShelfRepository {
    var inserted: [ShelfItemDraft] = []
    var items: [UUID: ShelfItem] = [:]
    func insert(_ draft: ShelfItemDraft) async throws -> ShelfItem { let item = ShelfItem(id: UUID(), kind: draft.kind, content: draft.content, source: draft.source, createdAt: draft.createdAt, expiresAt: draft.expiresAt); inserted.append(draft); items[item.id] = item; return item }
    nonisolated func importFile(_ request: FileImportRequest) -> AsyncThrowingStream<ImportProgress, Error> { .init { $0.finish(throwing: HandoffError.unsupportedInput) } }
    func item(id: UUID) async throws -> ShelfItem? { items[id] }
    func list(_ query: ShelfQuery) async throws -> [ShelfItem] { Array(items.values) }
    func setFavorite(id: UUID, isFavorite: Bool) async throws -> ShelfItem { items[id]! }
    func setTaskComplete(id: UUID, isComplete: Bool) async throws -> ShelfItem { items[id]! }
    func export(id: UUID, to destination: URL) async throws -> ExportReceipt { .init(destination: destination) }
    func delete(id: UUID) async throws { items[id] = nil }
    func purgeExpired(before date: Date) async throws -> PurgeReport { let ids = items.values.filter { $0.expiresAt.map { $0 < date } ?? false }.map(\.id); for id in ids { items[id] = nil }; return .init(deletedIDs: ids) }
}
