import Foundation
import Security
import AutomationDomain

public actor CredentialStore {
    private let service: String
    public init(service: String = "com.ledge.automation") { self.service = service }
    public func read(_ name: String) throws -> Data? {
        var query = base(name); query[kSecReturnData] = true; query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw PlatformError.unavailable("Keychain unavailable (\(status))") }
        return result as? Data
    }
    public func write(_ data: Data, name: String) throws {
        let query = base(name)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if result == errSecItemNotFound {
            var item = query; item[kSecValueData] = data; item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PlatformError.unavailable("Cannot save connection in Keychain") }
        } else if result != errSecSuccess { throw PlatformError.unavailable("Cannot update connection in Keychain") }
    }
    public func delete(_ name: String) throws {
        let result = SecItemDelete(base(name) as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw PlatformError.unavailable("Cannot disconnect Keychain item") }
    }
    public func masterKey(allowCreation: Bool) throws -> Data {
        if let key = try read("master-key-v1") { return key }
        guard allowCreation else { throw PlatformError.unavailable("Existing automation data has no accessible key. Restore Keychain access; data was not reset.") }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw PlatformError.unavailable("Cannot generate encryption key") }
        let data = Data(bytes); try write(data, name: "master-key-v1"); return data
    }
    private func base(_ name: String) -> [CFString: Any] { [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: name, kSecAttrSynchronizable: false] }
}
