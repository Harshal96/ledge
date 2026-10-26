import CryptoKit
import Foundation
import LedgeDomain
import LedgeStorage
import XCTest

final class FileVaultImportPerformanceTests: XCTestCase {
    func testEncryptedPayloadRoundTripAtBoundedFixtureSize() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ledge-performance-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = EncryptedPayloadVault(root: root, keyStore: FixedPerformanceKeyStore())
        let id = UUID()
        let bytes = Data(repeating: 0x42, count: 1_048_576)
        measure {
            let expectation = expectation(description: "vault")
            Task {
                try? await vault.write(bytes, itemID: id, kind: .trayFile)
                _ = try? await vault.read(itemID: id, kind: .trayFile)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 10)
        }
    }
}

private struct FixedPerformanceKeyStore: MasterKeyStoring {
    func loadOrCreate() throws -> SymmetricKey { SymmetricKey(data: Data(repeating: 7, count: 32)) }
}
