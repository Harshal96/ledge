import CryptoKit
import Foundation
import LedgeDomain

public struct ReconciliationReport: Sendable, Equatable { public let removedIncoming: Int; public let missingPayloads: Int; public init(removedIncoming: Int = 0, missingPayloads: Int = 0) { self.removedIncoming = removedIncoming; self.missingPayloads = missingPayloads } }

public actor EncryptedPayloadVault {
    private let root: URL
    private let keyStore: any MasterKeyStoring
    public init(root: URL, keyStore: any MasterKeyStoring) { self.root = root; self.keyStore = keyStore }

    public func write(_ data: Data, itemID: UUID, kind: ShelfItemKind) async throws {
        let key = try keyStore.loadOrCreate()
        try ensureDirectories()
        let encrypted = try PayloadEnvelope.seal(data, id: itemID, kind: kind, key: key)
        let incoming = root.appending(path: "Vault/.incoming/\(UUID().uuidString)")
        let target = payloadURL(itemID)
        try encrypted.write(to: incoming, options: [.atomic])
        try setMode(incoming, 0o600)
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: incoming, backupItemName: nil, options: [])
        } else {
            try FileManager.default.moveItem(at: incoming, to: target)
        }
        try setMode(target, 0o600)
    }

    public func importFile(from source: URL, itemID: UUID, kind: ShelfItemKind) -> AsyncThrowingStream<ImportProgress, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                do { let data = try Data(contentsOf: source); try await self?.write(data, itemID: itemID, kind: kind); continuation.yield(.init(completedBytes: Int64(data.count), totalBytes: Int64(data.count))); continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
        }
    }

    public func read(itemID: UUID, kind: ShelfItemKind) async throws -> Data {
        guard FileManager.default.fileExists(atPath: payloadURL(itemID).path) else { throw PayloadVaultError.missingPayload }
        return try PayloadEnvelope.open(Data(contentsOf: payloadURL(itemID)), id: itemID, kind: kind, key: keyStore.loadOrCreate())
    }
    public func export(itemID: UUID, kind: ShelfItemKind, to destination: URL) async throws { try await read(itemID: itemID, kind: kind).write(to: destination, options: .atomic) }
    public func delete(itemID: UUID) async throws { let url = payloadURL(itemID); if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
    public func reconcile() async throws -> ReconciliationReport {
        try ensureDirectories()
        let incoming = root.appending(path: "Vault/.incoming")
        let files = try FileManager.default.contentsOfDirectory(at: incoming, includingPropertiesForKeys: nil)
        for file in files { try? FileManager.default.removeItem(at: file) }
        return ReconciliationReport(removedIncoming: files.count)
    }

    private func payloadURL(_ id: UUID) -> URL { root.appending(path: "Vault/\(id.uuidString).ledge") }
    private func ensureDirectories() throws {
        for component in [root, root.appending(path: "Vault"), root.appending(path: "Vault/.incoming")] {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: component.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue, try component.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw PayloadVaultError.fileSystem }
            } else { try FileManager.default.createDirectory(at: component, withIntermediateDirectories: true); try setMode(component, 0o700) }
            var values = URLResourceValues(); values.isExcludedFromBackup = true; var mutable = component; try mutable.setResourceValues(values)
        }
    }
    private func setMode(_ url: URL, _ mode: Int16) throws { try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: url.path) }
}
