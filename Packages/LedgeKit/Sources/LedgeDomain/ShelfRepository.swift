import Foundation

public struct ImportProgress: Sendable, Equatable {
    public let completedBytes: Int64
    public let totalBytes: Int64
    public init(completedBytes: Int64, totalBytes: Int64) { self.completedBytes = completedBytes; self.totalBytes = totalBytes }
}

public struct FileImportRequest: Sendable {
    public let source: URL
    public let draft: ShelfItemDraft
    public init(source: URL, draft: ShelfItemDraft) { self.source = source; self.draft = draft }
}

public struct ShelfQuery: Sendable { public init() {} }
public struct ExportReceipt: Sendable, Equatable { public let destination: URL; public init(destination: URL) { self.destination = destination } }
public struct PurgeReport: Sendable, Equatable { public let deletedIDs: [UUID]; public let sourceClearedIDs: [UUID]; public init(deletedIDs: [UUID] = [], sourceClearedIDs: [UUID] = []) { self.deletedIDs = deletedIDs; self.sourceClearedIDs = sourceClearedIDs } }

public protocol ShelfRepository: Sendable {
    func insert(_ draft: ShelfItemDraft) async throws -> ShelfItem
    /// Stores binary payload bytes directly in the encrypted repository; callers must not create a plaintext file first.
    func insertBinary(_ draft: ShelfItemDraft, bytes: Data) async throws -> ShelfItem
    func importFile(_ request: FileImportRequest) -> AsyncThrowingStream<ImportProgress, Error>
    func item(id: UUID) async throws -> ShelfItem?
    func list(_ query: ShelfQuery) async throws -> [ShelfItem]
    func setFavorite(id: UUID, isFavorite: Bool) async throws -> ShelfItem
    func setTaskComplete(id: UUID, isComplete: Bool) async throws -> ShelfItem
    func export(id: UUID, to destination: URL) async throws -> ExportReceipt
    func delete(id: UUID) async throws
    func purgeExpired(before date: Date) async throws -> PurgeReport
}

public enum ShelfRepositoryError: Error, Sendable, Equatable { case binaryPersistenceUnavailable }

public extension ShelfRepository {
    func insertBinary(_ draft: ShelfItemDraft, bytes: Data) async throws -> ShelfItem { throw ShelfRepositoryError.binaryPersistenceUnavailable }
}
