import CryptoKit
import Foundation
import Testing
@testable import LedgeStorage
import LedgeDomain

@Test("Expiry removes ordinary items and preserves favorites")
func expiryPolicy() async throws {
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    let root = try makeStoreDirectory()
    let store = try SQLiteShelfStore(root: root, keyStore: TestStoreKey())
    let ordinary = try await store.insert(.note("short lived", now: now))
    let favorite = try await store.insert(.note("keep", now: now))
    _ = try await store.setFavorite(id: favorite.id, isFavorite: true)

    let report = try await store.purgeExpired(before: now.addingTimeInterval(31 * 86_400))
    #expect(report.deletedIDs == [ordinary.id])
    #expect(try await store.item(id: favorite.id)?.isFavorite == true)
}

@Test("Pinned captures retire source context without deleting content")
func pinnedSourceRetirement() async throws {
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    let root = try makeStoreDirectory()
    let store = try SQLiteShelfStore(root: root, keyStore: TestStoreKey())
    let source = SourceContext(bundleIdentifier: "com.example.editor", applicationName: "Editor", capturedAt: now)
    let draft = ShelfItemDraft(kind: .note, content: .text("keep this"), source: source, createdAt: now, expiresAt: now.addingTimeInterval(30 * 86_400))
    let item = try await store.insert(draft)
    _ = try await store.setFavorite(id: item.id, isFavorite: true)

    let report = try await store.purgeExpired(before: now.addingTimeInterval(8 * 86_400))
    #expect(report.sourceClearedIDs == [item.id])
    let retained = try await store.item(id: item.id)
    #expect(retained?.content == .text("keep this"))
    #expect(retained?.source == nil)

    let vault = EncryptedPayloadVault(root: root, keyStore: TestStoreKey())
    let sealedPayload = try await vault.read(itemID: item.id, kind: .note)
    #expect(String(decoding: sealedPayload, as: UTF8.self).contains("com.example.editor") == false)
}

@Test("Reconciliation fails closed when the keychain is unavailable")
func reconciliationPreservesRowsOnKeychainFailure() async throws {
    let root = try makeStoreDirectory()
    let store = try SQLiteShelfStore(root: root, keyStore: TestStoreKey())
    let item = try await store.insert(.note("protected", now: Date(timeIntervalSince1970: 1_786_320_000)))
    let unavailable = try SQLiteShelfStore(root: root, keyStore: UnavailableKeyStore())

    await #expect(throws: PayloadVaultError.invalidKeychainItem) {
        try await unavailable.reconcile()
    }
    #expect(try await store.item(id: item.id)?.content == .text("protected"))
}

@Test("Pinned captures retain payload but retire source after seven days")
func pinnedCaptureRetiresSource() async throws {
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    let root = try makeStoreDirectory()
    let store = try SQLiteShelfStore(root: root, keyStore: TestStoreKey())
    let draft = ShelfItemDraft(kind: .note, content: .text("still here"), source: SourceContext(bundleIdentifier: "com.example.Editor", applicationName: "Editor", capturedAt: now), createdAt: now, expiresAt: now.addingTimeInterval(30 * 86_400))
    let item = try await store.insert(draft)
    _ = try await store.setFavorite(id: item.id, isFavorite: true)
    let report = try await store.purgeExpired(before: now.addingTimeInterval(8 * 86_400))
    let retained = try await store.item(id: item.id)
    #expect(report.sourceClearedIDs == [item.id])
    #expect(retained?.source == nil)
    #expect(retained?.content == .text("still here"))
}

@Test("Reconciliation is idempotent for completed state")
func repeatedReconciliation() async throws {
    let store = try SQLiteShelfStore(root: try makeStoreDirectory(), keyStore: TestStoreKey())
    let first = try await store.reconcile()
    let second = try await store.reconcile()
    #expect(first == second)
}

@Test("File import retains original bytes inside the encrypted payload")
func fileImportRetainsBytes() async throws {
    let root = try makeStoreDirectory()
    let source = root.appending(path: "source.bin")
    let expected = Data([0, 1, 2, 3, 255])
    try expected.write(to: source)
    let store = try SQLiteShelfStore(root: root, keyStore: TestStoreKey())
    let draft = ShelfItemDraft(kind: .trayFile, content: .binary(.init(displayName: "source.bin", byteCount: expected.count)), source: nil, createdAt: .now, expiresAt: nil)
    var progress: [ImportProgress] = []
    for try await update in store.importFile(.init(source: source, draft: draft)) { progress.append(update) }
    let item = try #require(try await store.list(ShelfQuery()).first)
    let destination = root.appending(path: "export.bin")
    _ = try await store.export(id: item.id, to: destination)
    #expect(try Data(contentsOf: destination) == expected)
    #expect(progress.last?.completedBytes == Int64(expected.count))
}

private struct TestStoreKey: MasterKeyStoring {
    func loadOrCreate() throws -> CryptoKit.SymmetricKey { CryptoKit.SymmetricKey(data: Data(repeating: 7, count: 32)) }
}

private struct UnavailableKeyStore: MasterKeyStoring {
    func loadOrCreate() throws -> CryptoKit.SymmetricKey { throw PayloadVaultError.invalidKeychainItem }
}

private func makeStoreDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "ledge-store-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
