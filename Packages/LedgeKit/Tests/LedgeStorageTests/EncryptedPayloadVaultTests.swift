import CryptoKit
import Foundation
import Testing
@testable import LedgeStorage
import LedgeDomain

private struct FixedKeyStore: MasterKeyStoring {
    let bytes: Data

    init(_ bytes: Data) { self.bytes = bytes }
    func loadOrCreate() throws -> SymmetricKey { SymmetricKey(data: bytes) }
}

@Test("Encrypted payload round trips without plaintext at rest")
func encryptedRoundTrip() async throws {
    let root = try makeTestDirectory()
    let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let secret = Data("customer roadmap and token sk_live_example".utf8)
    let vault = EncryptedPayloadVault(root: root, keyStore: FixedKeyStore(Data(repeating: 0x2A, count: 32)))

    try await vault.write(secret, itemID: id, kind: .note)
    let stored = try Data(contentsOf: root.appending(path: "Vault/\(id.uuidString).ledge"))

    #expect(stored.range(of: secret) == nil)
    #expect(try await vault.read(itemID: id, kind: .note) == secret)
}

@Test("Wrong key fails closed")
func wrongKeyFailsClosed() async throws {
    let root = try makeTestDirectory()
    let id = UUID()
    try await EncryptedPayloadVault(root: root, keyStore: FixedKeyStore(Data(repeating: 1, count: 32)))
        .write(Data("private".utf8), itemID: id, kind: .clipboardText)

    let reader = EncryptedPayloadVault(root: root, keyStore: FixedKeyStore(Data(repeating: 2, count: 32)))
    await #expect(throws: PayloadVaultError.authenticationFailed) {
        try await reader.read(itemID: id, kind: .clipboardText)
    }
}

@Test("Metadata and plaintext both authenticate")
func rejectsWrongKind() async throws {
    let root = try makeTestDirectory()
    let id = UUID()
    let vault = EncryptedPayloadVault(root: root, keyStore: FixedKeyStore(Data(repeating: 3, count: 32)))
    try await vault.write(Data("short lived".utf8), itemID: id, kind: .note)
    await #expect(throws: PayloadVaultError.authenticationFailed) {
        try await vault.read(itemID: id, kind: .task)
    }
}

private func makeTestDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "ledge-storage-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
