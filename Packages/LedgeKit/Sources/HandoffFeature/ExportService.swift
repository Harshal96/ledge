import Foundation
import LedgeDomain

public enum HandoffExportMode: Sendable, Equatable { case copy, moveFromShelf }

public actor ExportService {
    private let repository: any ShelfRepository
    public init(repository: any ShelfRepository) { self.repository = repository }
    public func export(_ id: UUID, to destination: URL, mode: HandoffExportMode) async throws {
        let temporary = destination.deletingLastPathComponent().appending(path: ".ledge-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = try await repository.export(id: id, to: temporary)
        guard FileManager.default.fileExists(atPath: temporary.path), (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) != nil else { throw HandoffError.corruptedExport }
        if FileManager.default.fileExists(atPath: destination.path) { throw HandoffError.overwriteNotConfirmed }
        try FileManager.default.moveItem(at: temporary, to: destination)
        if mode == .moveFromShelf { try await repository.delete(id: id) }
    }
}
