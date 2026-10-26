import CryptoKit
import Foundation
import Security

public protocol MasterKeyStoring: Sendable { func loadOrCreate() throws -> SymmetricKey }

public struct KeychainMasterKeyStore: MasterKeyStoring {
    private let service: String
    private let account: String
    public init(service: String, account: String = "master-key") { self.service = service; self.account = account }
    public func loadOrCreate() throws -> SymmetricKey {
        let base: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecAttrSynchronizable: kCFBooleanFalse as Any, kSecUseDataProtectionKeychain: kCFBooleanTrue as Any]
        var query = base; query[kSecReturnData] = kCFBooleanTrue
        var result: CFTypeRef?
        let found = SecItemCopyMatching(query as CFDictionary, &result)
        if found == errSecSuccess, let bytes = result as? Data, bytes.count == 32 { return SymmetricKey(data: bytes) }
        guard found == errSecItemNotFound else { throw PayloadVaultError.invalidKeychainItem }
        var bytes = Data(count: 32)
        guard bytes.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }) == errSecSuccess else { throw PayloadVaultError.invalidKeychainItem }
        var add = base; add[kSecValueData] = bytes; add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess { return SymmetricKey(data: bytes) }
        if status == errSecDuplicateItem { return try loadOrCreate() }
        throw PayloadVaultError.invalidKeychainItem
    }
}
