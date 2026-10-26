import Foundation
import LedgeDomain

public actor HandoffService {
    public static let maximumVaultBytes: Int64 = 1_024 * 1_024 * 1_024
    private let repository: any ShelfRepository
    private let exporter: ExportService
    public init(repository: any ShelfRepository, exporter: ExportService? = nil) { self.repository = repository; self.exporter = exporter ?? ExportService(repository: repository) }
    public func importPayload(_ payload: IncomingPayload, expiry: HandoffExpiry = .oneDay, now: Date = .now) async throws -> ShelfItem {
        let draft = ShelfItemDraft(kind: payload.shelfKind, content: payload.content, source: nil, createdAt: now, expiresAt: expiry.date(from: now))
        switch payload {
        case let .file(file):
            defer { file.close() }
            let usage = try await vaultUsage()
            guard usage + Int64(file.descriptor.byteCount) <= Self.maximumVaultBytes else { throw HandoffError.vaultCapacityExceeded }
            // Consume the descriptor we validated and held open. Re-opening the
            // user URL here would reintroduce a TOCTOU race between validation
            // and persistence; the repository receives the bytes directly and
            // seals them without creating a plaintext staging file.
            let bytes = try file.readData()
            return try await repository.insertBinary(draft, bytes: bytes)
        default: return try await repository.insert(draft)
        }
    }
    public func export(_ id: UUID, to destination: URL, mode: HandoffExportMode) async throws { try await exporter.export(id, to: destination, mode: mode) }
    public func deleteAll() async throws { for item in try await repository.list(ShelfQuery()) { try await repository.delete(id: item.id) } }
    public func cleanup(now: Date = .now) async throws -> PurgeReport { try await repository.purgeExpired(before: now) }
    public func list() async throws -> [ShelfItem] { try await repository.list(ShelfQuery()) }
    private func vaultUsage() async throws -> Int64 { try await repository.list(ShelfQuery()).reduce(0) { result, item in if case let .binary(descriptor) = item.content { return result + Int64(descriptor.byteCount) }; return result } }
}
