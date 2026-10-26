import CryptoKit
import Foundation
import LedgeDomain
import SQLite3

public actor SQLiteShelfStore: ShelfRepository {
    private let connection: SQLiteConnection
    private let vault: EncryptedPayloadVault
    private let keyStore: any MasterKeyStoring

    public init(root: URL, keyStore: any MasterKeyStoring) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.connection = try SQLiteConnection(url: root.appending(path: "ledge.sqlite"))
        try ShelfMigration.apply(to: connection)
        self.vault = EncryptedPayloadVault(root: root, keyStore: keyStore)
        self.keyStore = keyStore
    }

    public func insert(_ draft: ShelfItemDraft) async throws -> ShelfItem {
        let item = ShelfItem(id: UUID(), kind: draft.kind, content: draft.content, source: draft.source, createdAt: draft.createdAt, expiresAt: draft.expiresAt)
        let payload = try JSONEncoder().encode(StoredPayload(item: item, fileBytes: nil))
        let digest = try hmac(payload)
        let operationID = UUID()
        try connection.transaction {
            let statement = try connection.prepare("INSERT INTO shelf_item (id,kind,created_at,expires_at,is_favorite,state,payload_path,payload_bytes,keyed_digest) VALUES (?,?,?,?,0,'importing',?,?,?)")
            defer { sqlite3_finalize(statement) }
            bind(item.id.uuidString, at: 1, statement); bind(item.kind.rawValue, at: 2, statement); bind(item.createdAt.timeIntervalSince1970, at: 3, statement); bind(item.expiresAt?.timeIntervalSince1970, at: 4, statement); bind("Vault/\(item.id.uuidString).ledge", at: 5, statement); bind(Int64(payload.count), at: 6, statement); bind(digest, at: 7, statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw PayloadVaultError.fileSystem }
            try insertOperation(operationID, itemID: item.id, operation: "import", stage: "rowInserted", at: item.createdAt)
        }
        do { try await vault.write(payload, itemID: item.id, kind: item.kind) } catch { throw error }
        try connection.transaction { try updateOperation(operationID, stage: "renamed"); try updateState(item.id, "ready"); try deleteOperation(operationID) }
        return item
    }

    public func insertBinary(_ draft: ShelfItemDraft, bytes: Data) async throws -> ShelfItem { try await insertFile(draft, bytes: bytes) }

    public nonisolated func importFile(_ request: FileImportRequest) -> AsyncThrowingStream<ImportProgress, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in do { let data = try Data(contentsOf: request.source); _ = try await self?.insertFile(request.draft, bytes: data); continuation.yield(.init(completedBytes: Int64(data.count), totalBytes: Int64(data.count))); continuation.finish() } catch { continuation.finish(throwing: error) } }
        }
    }
    public func item(id: UUID) async throws -> ShelfItem? { try await readItem(id) }
    public func list(_ query: ShelfQuery) async throws -> [ShelfItem] {
        let statement = try connection.prepare("SELECT id, kind FROM shelf_item WHERE state='ready' ORDER BY created_at DESC"); defer { sqlite3_finalize(statement) }; var result: [ShelfItem] = []
        while sqlite3_step(statement) == SQLITE_ROW, let idString = sqliteText(statement, 0), let id = UUID(uuidString: idString) { if let item = try await readItem(id) { result.append(item) } }
        return result
    }
    public func setFavorite(id: UUID, isFavorite: Bool) async throws -> ShelfItem { try updateFavorite(id, isFavorite); guard let value = try await readItem(id) else { throw PayloadVaultError.missingPayload }; return value }
    public func setTaskComplete(id: UUID, isComplete: Bool) async throws -> ShelfItem { guard var item = try await readItem(id) else { throw PayloadVaultError.missingPayload }; guard case let .task(title, _) = item.content else { return item }; item = ShelfItem(id: item.id, kind: item.kind, content: .task(title: title, isComplete: isComplete), source: item.source, createdAt: item.createdAt, expiresAt: item.expiresAt, isFavorite: item.isFavorite); try await rewrite(item); return item }
    public func export(id: UUID, to destination: URL) async throws -> ExportReceipt { guard let stored = try await readStored(id), let bytes = stored.fileBytes else { throw PayloadVaultError.missingPayload }; try bytes.write(to: destination, options: .atomic); return ExportReceipt(destination: destination) }
    public func delete(id: UUID) async throws { let operationID = UUID(); try connection.transaction { try updateState(id, "deleting"); try insertOperation(operationID, itemID: id, operation: "delete", stage: "marked", at: .now) }; try await vault.delete(itemID: id); try connection.transaction { try deleteRow(id); try deleteOperation(operationID) } }
    public func purgeExpired(before date: Date) async throws -> PurgeReport {
        let values = try await list(ShelfQuery()); var deleted: [UUID] = []; var cleared: [UUID] = []
        for item in values {
            if let expires = item.expiresAt, expires < date, !item.isFavorite { try await delete(id: item.id); deleted.append(item.id); continue }
            if item.isFavorite, item.source != nil, item.createdAt.addingTimeInterval(7 * 86_400) < date { let revised = ShelfItem(id: item.id, kind: item.kind, content: item.content, source: nil, createdAt: item.createdAt, expiresAt: item.expiresAt, isFavorite: true); try await rewrite(revised); cleared.append(item.id) }
        }
        return PurgeReport(deletedIDs: deleted, sourceClearedIDs: cleared)
    }

    public func reconcile() async throws -> ReconciliationReport { let vaultReport = try await vault.reconcile(); let statement = try connection.prepare("SELECT id,kind,state FROM shelf_item WHERE state != 'ready' OR state = 'ready'"); defer { sqlite3_finalize(statement) }; var missing = vaultReport.missingPayloads; while sqlite3_step(statement) == SQLITE_ROW, let string = sqliteText(statement, 0), let id = UUID(uuidString: string), let kindRaw = sqliteText(statement, 1), let kind = ShelfItemKind(rawValue: kindRaw) { let state = sqliteText(statement, 2) ?? ""; if state == "deleting" { try? await vault.delete(itemID: id); try deleteRow(id); continue }; do { _ = try await vault.read(itemID: id, kind: kind); if state == "importing" { try updateState(id, "ready") } } catch let error as PayloadVaultError { guard case .missingPayload = error else { throw error }; try deleteRow(id); missing += 1 } }; try connection.execute("DELETE FROM storage_operation"); return ReconciliationReport(removedIncoming: vaultReport.removedIncoming, missingPayloads: missing) }
    private func readItem(_ id: UUID) async throws -> ShelfItem? { guard let stored = try await readStored(id) else { return nil }; return stored.shelfItem }
    private func readStored(_ id: UUID) async throws -> StoredPayload? { let statement = try connection.prepare("SELECT kind,is_favorite,state FROM shelf_item WHERE id=?"); defer { sqlite3_finalize(statement) }; bind(id.uuidString, at: 1, statement); guard sqlite3_step(statement) == SQLITE_ROW, sqliteText(statement, 2) == "ready", let raw = sqliteText(statement, 0), let kind = ShelfItemKind(rawValue: raw) else { return nil }; let payload = try await vault.read(itemID: id, kind: kind); var stored = try JSONDecoder().decode(StoredPayload.self, from: payload); if sqlite3_column_int(statement, 1) != 0 { let item = stored.shelfItem; stored = StoredPayload(item: ShelfItem(id: item.id, kind: item.kind, content: item.content, source: item.source, createdAt: item.createdAt, expiresAt: item.expiresAt, isFavorite: true), fileBytes: stored.fileBytes) }; return stored }
    private func rewrite(_ item: ShelfItem) async throws { let previous = try await readStored(item.id); let payload = try JSONEncoder().encode(StoredPayload(item: item, fileBytes: previous?.fileBytes)); try await vault.write(payload, itemID: item.id, kind: item.kind); try updateMetadata(item.id, bytes: payload.count, digest: try hmac(payload), favorite: item.isFavorite) }
    private func insertFile(_ draft: ShelfItemDraft, bytes: Data) async throws -> ShelfItem { let item = ShelfItem(id: UUID(), kind: draft.kind, content: draft.content, source: draft.source, createdAt: draft.createdAt, expiresAt: draft.expiresAt); let payload = try JSONEncoder().encode(StoredPayload(item: item, fileBytes: bytes)); let digest = try hmac(payload); let operationID = UUID(); try connection.transaction { let statement = try connection.prepare("INSERT INTO shelf_item (id,kind,created_at,expires_at,is_favorite,state,payload_path,payload_bytes,keyed_digest) VALUES (?,?,?,?,0,'importing',?,?,?)"); defer { sqlite3_finalize(statement) }; bind(item.id.uuidString, at: 1, statement); bind(item.kind.rawValue, at: 2, statement); bind(item.createdAt.timeIntervalSince1970, at: 3, statement); bind(item.expiresAt?.timeIntervalSince1970, at: 4, statement); bind("Vault/\(item.id.uuidString).ledge", at: 5, statement); bind(Int64(payload.count), at: 6, statement); bind(digest, at: 7, statement); guard sqlite3_step(statement) == SQLITE_DONE else { throw PayloadVaultError.fileSystem }; try insertOperation(operationID, itemID: item.id, operation: "import", stage: "rowInserted", at: item.createdAt) }; try await vault.write(payload, itemID: item.id, kind: item.kind); try connection.transaction { try updateOperation(operationID, stage: "renamed"); try updateState(item.id, "ready"); try deleteOperation(operationID) }; return item }
    private func hmac(_ data: Data) throws -> Data { let master = try keyStore.loadOrCreate(); let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: Data(), info: Data("Ledge keyed digest v1".utf8), outputByteCount: 32); return Data(HMAC<SHA256>.authenticationCode(for: data, using: key)) }
    private func updateState(_ id: UUID, _ state: String) throws { let statement = try connection.prepare("UPDATE shelf_item SET state=? WHERE id=?"); defer { sqlite3_finalize(statement) }; bind(state, at: 1, statement); bind(id.uuidString, at: 2, statement); guard sqlite3_step(statement) == SQLITE_DONE else { throw PayloadVaultError.fileSystem } }
    private func updateFavorite(_ id: UUID, _ favorite: Bool) throws { let statement = try connection.prepare("UPDATE shelf_item SET is_favorite=? WHERE id=?"); defer { sqlite3_finalize(statement) }; bind(Int32(favorite ? 1 : 0), at: 1, statement); bind(id.uuidString, at: 2, statement); guard sqlite3_step(statement) == SQLITE_DONE else { throw PayloadVaultError.fileSystem } }
    private func updateMetadata(_ id: UUID, bytes: Int, digest: Data, favorite: Bool) throws { let statement = try connection.prepare("UPDATE shelf_item SET payload_bytes=?, keyed_digest=?, is_favorite=? WHERE id=?"); defer { sqlite3_finalize(statement) }; bind(Int64(bytes), at: 1, statement); bind(digest, at: 2, statement); bind(Int32(favorite ? 1 : 0), at: 3, statement); bind(id.uuidString, at: 4, statement); guard sqlite3_step(statement) == SQLITE_DONE else { throw PayloadVaultError.fileSystem } }
    private func insertOperation(_ id: UUID, itemID: UUID, operation: String, stage: String, at: Date) throws { let statement = try connection.prepare("INSERT INTO storage_operation (id,item_id,operation,stage,created_at) VALUES (?,?,?,?,?)"); defer { sqlite3_finalize(statement) }; bind(id.uuidString, at: 1, statement); bind(itemID.uuidString, at: 2, statement); bind(operation, at: 3, statement); bind(stage, at: 4, statement); bind(at.timeIntervalSince1970, at: 5, statement); guard sqlite3_step(statement) == SQLITE_DONE else { throw PayloadVaultError.fileSystem } }
    private func updateOperation(_ id: UUID, stage: String) throws { let statement = try connection.prepare("UPDATE storage_operation SET stage=? WHERE id=?"); defer { sqlite3_finalize(statement) }; bind(stage, at: 1, statement); bind(id.uuidString, at: 2, statement); guard sqlite3_step(statement) == SQLITE_DONE else { throw PayloadVaultError.fileSystem } }
    private func deleteOperation(_ id: UUID) throws { let statement = try connection.prepare("DELETE FROM storage_operation WHERE id=?"); defer { sqlite3_finalize(statement) }; bind(id.uuidString, at: 1, statement); guard sqlite3_step(statement) == SQLITE_DONE else { throw PayloadVaultError.fileSystem } }
    private func deleteRow(_ id: UUID) throws { let statement = try connection.prepare("DELETE FROM shelf_item WHERE id=?"); defer { sqlite3_finalize(statement) }; bind(id.uuidString, at: 1, statement); guard sqlite3_step(statement) == SQLITE_DONE else { throw PayloadVaultError.fileSystem } }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func bind(_ value: String, at index: Int32, _ statement: OpaquePointer) { sqlite3_bind_text(statement, index, value, -1, sqliteTransient) }
private func bind(_ value: Double?, at index: Int32, _ statement: OpaquePointer) { if let value { sqlite3_bind_double(statement, index, value) } else { sqlite3_bind_null(statement, index) } }
private func bind(_ value: Int64, at index: Int32, _ statement: OpaquePointer) { sqlite3_bind_int64(statement, index, value) }
private func bind(_ value: Int32, at index: Int32, _ statement: OpaquePointer) { sqlite3_bind_int(statement, index, value) }
private func bind(_ value: Data, at index: Int32, _ statement: OpaquePointer) { value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), sqliteTransient) } }
private func sqliteText(_ statement: OpaquePointer, _ column: Int32) -> String? { sqlite3_column_text(statement, column).map { String(cString: $0) } }

private struct StoredPayload: Codable {
    let item: StoredItem
    let fileBytes: Data?
    init(item: ShelfItem, fileBytes: Data?) { self.item = StoredItem(item); self.fileBytes = fileBytes }
    struct StoredItem: Codable { let id: UUID; let kind: ShelfItemKind; let content: StoredContent; let source: SourceContext?; let createdAt: Date; let expiresAt: Date?; let isFavorite: Bool; init(_ item: ShelfItem) { id = item.id; kind = item.kind; content = .init(item.content); source = item.source; createdAt = item.createdAt; expiresAt = item.expiresAt; isFavorite = item.isFavorite }; var value: ShelfItem { ShelfItem(id: id, kind: kind, content: content.value, source: source, createdAt: createdAt, expiresAt: expiresAt, isFavorite: isFavorite) } }
    enum StoredContent: Codable { case text(String), url(URL), task(String, Bool), binary(String, Int, String?); init(_ value: ShelfContent) { switch value { case let .text(text): self = .text(text); case let .url(url): self = .url(url); case let .task(title, done): self = .task(title, done); case let .binary(value): self = .binary(value.displayName, value.byteCount, value.uniformTypeIdentifier) } }; var value: ShelfContent { switch self { case let .text(text): .text(text); case let .url(url): .url(url); case let .task(title, done): .task(title: title, isComplete: done); case let .binary(name, bytes, uti): .binary(.init(displayName: name, byteCount: bytes, uniformTypeIdentifier: uti)) } } }
}
private extension StoredPayload { var shelfItem: ShelfItem { item.value } }
