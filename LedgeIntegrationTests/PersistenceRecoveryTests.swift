import CryptoKit
import Foundation
import XCTest
@testable import LedgeStorage
import LedgeDomain

final class PersistenceRecoveryTests: XCTestCase {
    func testInterruptedIncomingPayloadIsRemovedIdempotently() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ledge-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Vault/.incoming"), withIntermediateDirectories: true)
        let stray = root.appending(path: "Vault/.incoming/interrupted")
        try Data([1, 2, 3]).write(to: stray)
        let vault = EncryptedPayloadVault(root: root, keyStore: RecoveryKey())
        let first = try await vault.reconcile()
        let second = try await vault.reconcile()
        XCTAssertEqual(first.removedIncoming, 1)
        XCTAssertEqual(second.removedIncoming, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stray.path))
    }

    func testMissingPayloadIsReconciledWithoutTouchingOtherRows() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ledge-recovery-store-\(UUID().uuidString)")
        let key = RecoveryKey()
        let store = try SQLiteShelfStore(root: root, keyStore: key)
        let item = try await store.insert(.note("recoverable", now: Date(timeIntervalSince1970: 1_786_320_000)))
        try FileManager.default.removeItem(at: root.appending(path: "Vault/\(item.id.uuidString).ledge"))

        let report = try await store.reconcile()
        XCTAssertEqual(report.missingPayloads, 1)
        let reconciledItem = try await store.item(id: item.id)
        XCTAssertNil(reconciledItem)
    }
}

private struct RecoveryKey: MasterKeyStoring { func loadOrCreate() throws -> SymmetricKey { SymmetricKey(data: Data(repeating: 9, count: 32)) } }
