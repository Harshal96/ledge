import Foundation
import Testing
import LedgeDomain
@testable import HandoffFeature

@Test("Move deletes only after a verified export while copy retains the shelf item")
func exportModes() async throws {
    let repository = ExportRepository()
    let service = HandoffService(repository: repository)
    let copyDestination = FileManager.default.temporaryDirectory.appending(path: "ledge-export-copy-\(UUID().uuidString)")
    let moveDestination = FileManager.default.temporaryDirectory.appending(path: "ledge-export-move-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: copyDestination); try? FileManager.default.removeItem(at: moveDestination) }
    try await service.export(repository.onlyID, to: copyDestination, mode: .copy)
    #expect(await repository.deleted == false)
    try await service.export(repository.onlyID, to: moveDestination, mode: .moveFromShelf)
    #expect(await repository.deleted == true)
}

private actor ExportRepository: ShelfRepository {
    let onlyID = UUID(); var deleted = false
    func insert(_ draft: ShelfItemDraft) async throws -> ShelfItem { fatalError() }
    nonisolated func importFile(_ request: FileImportRequest) -> AsyncThrowingStream<ImportProgress, Error> { fatalError() }
    func item(id: UUID) async throws -> ShelfItem? { ShelfItem(id: onlyID, kind: .trayFile, content: .binary(.init(displayName: "report.pdf", byteCount: 3)), source: nil, createdAt: .now, expiresAt: nil) }
    func list(_ query: ShelfQuery) async throws -> [ShelfItem] { [] }
    func setFavorite(id: UUID, isFavorite: Bool) async throws -> ShelfItem { fatalError() }; func setTaskComplete(id: UUID, isComplete: Bool) async throws -> ShelfItem { fatalError() }
    func export(id: UUID, to destination: URL) async throws -> ExportReceipt { try Data([1,2,3]).write(to: destination); return .init(destination: destination) }
    func delete(id: UUID) async throws { deleted = true }
    func purgeExpired(before date: Date) async throws -> PurgeReport { .init() }
}
