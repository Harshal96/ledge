import Foundation
import Security
import SwiftUI
import LedgeDomain
import LedgeStorage

struct StorageUsageReport: Equatable {
    let vaultBytes: Int64
    let databaseBytes: Int64
    let exportCacheBytes: Int64

    var totalBytes: Int64 { vaultBytes + databaseBytes + exportCacheBytes }
    static let empty = StorageUsageReport(vaultBytes: 0, databaseBytes: 0, exportCacheBytes: 0)
}

enum StorageRecoveryError: Error, LocalizedError {
    case cleanupFailed

    var errorDescription: String? { "Some Ledge data could not be removed. Relaunch to retry cleanup." }
}

/// Filesystem/keychain boundary for the explicit Delete All action. It never
/// runs at initialization, and does not claim physical secure erase.
struct LedgeDataPurger {
    static let cleanupPendingKey = "ledge.recovery.cleanupPending"
    let root: URL
    let defaults: UserDefaults
    let keychainService: String

    init(
        root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ledge", isDirectory: true),
        defaults: UserDefaults = .standard,
        keychainService: String = Bundle.main.bundleIdentifier ?? "com.ledge.app"
    ) {
        self.root = root
        self.defaults = defaults
        self.keychainService = keychainService
    }

    func usage() -> StorageUsageReport {
        StorageUsageReport(
            vaultBytes: byteCount(root.appendingPathComponent("Vault", isDirectory: true)),
            databaseBytes: ["ledge.sqlite", "ledge.sqlite-wal", "ledge.sqlite-shm"].reduce(0) { $0 + byteCount(root.appendingPathComponent($1)) },
            exportCacheBytes: byteCount(root.appendingPathComponent("Exports", isDirectory: true))
        )
    }

    func deleteAll() throws {
        defaults.set(true, forKey: Self.cleanupPendingKey)
        // Delete the key first. Remaining ciphertext is intentionally unreadable
        // if a later filesystem operation is interrupted.
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: "master-key",
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain: kCFBooleanTrue as Any
        ]
        let keyStatus = SecItemDelete(query as CFDictionary)
        guard keyStatus == errSecSuccess || keyStatus == errSecItemNotFound else { throw StorageRecoveryError.cleanupFailed }

        for path in [
            root.appendingPathComponent("Vault", isDirectory: true),
            root.appendingPathComponent("Exports", isDirectory: true),
            root.appendingPathComponent("ledge.sqlite"),
            root.appendingPathComponent("ledge.sqlite-wal"),
            root.appendingPathComponent("ledge.sqlite-shm")
        ] where FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("ledge.") {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: Self.cleanupPendingKey)
    }

    var cleanupPending: Bool { defaults.bool(forKey: Self.cleanupPendingKey) }

    private func byteCount(_ url: URL) -> Int64 {
        guard let values = try? FileManager.default.attributesOfItem(atPath: url.path), let size = values[.size] as? NSNumber else {
            guard let files = try? FileManager.default.subpathsOfDirectory(atPath: url.path) else { return 0 }
            return files.reduce(0) { total, relative in
                let fileURL = url.appendingPathComponent(relative)
                let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                let size = attributes.flatMap { $0[.size] as? NSNumber }?.int64Value ?? 0
                return total + size
            }
        }
        return size.int64Value
    }
}

struct StorageSettingsView: View {
    private let purger: LedgeDataPurger
    private let clearExpiredAction: @MainActor () -> Void
    private let deleteClipboardHistoryAction: @MainActor () -> Void
    @State private var report = StorageUsageReport.empty
    @State private var showClipboardConfirmation = false
    @State private var showDeleteAllConfirmation = false
    @State private var statusMessage: String?

    init(
        purger: LedgeDataPurger = LedgeDataPurger(),
        clearExpired: @escaping @MainActor () -> Void = StorageSettingsView.performClearExpired,
        deleteClipboardHistory: @escaping @MainActor () -> Void = StorageSettingsView.performDeleteClipboardHistory
    ) {
        self.purger = purger
        self.clearExpiredAction = clearExpired
        self.deleteClipboardHistoryAction = deleteClipboardHistory
    }

    var body: some View {
        Form {
            Section("Local storage") {
                LabeledContent("Encrypted vault", value: byteString(report.vaultBytes))
                LabeledContent("SQLite metadata", value: byteString(report.databaseBytes))
                LabeledContent("Export cache", value: byteString(report.exportCacheBytes))
                LabeledContent("Total", value: byteString(report.totalBytes))
                Button("Refresh usage") { report = purger.usage() }.frame(minHeight: 44)
            }
            Section("Cleanup") {
                Button("Clear Expired") {
                    clearExpiredAction()
                    statusMessage = "Expired unpinned items are queued for cleanup."
                }
                    .frame(minHeight: 44)
                    .accessibilityHint("Removes expired unpinned shelf items and clears stale source context.")
                Button("Delete Clipboard History", role: .destructive) { showClipboardConfirmation = true }
                    .frame(minHeight: 44)
                Button("Delete All Ledge Data", role: .destructive) { showDeleteAllConfirmation = true }
                    .frame(minHeight: 44)
                Text("Delete All removes the Ledge key, encrypted vault, SQLite files, export cache, and Ledge preferences. macOS-managed permission decisions stay in System Settings. This is not a physical secure erase.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let statusMessage { Text(statusMessage).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            report = purger.usage()
            if purger.cleanupPending { statusMessage = "Recovery cleanup is pending; remaining payloads cannot be read until cleanup finishes." }
        }
        .confirmationDialog("Delete Clipboard History?", isPresented: $showClipboardConfirmation, titleVisibility: .visible) {
            Button("Delete Clipboard History", role: .destructive) {
                deleteClipboardHistoryAction()
                statusMessage = "Clipboard history deleted."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes only Ledge's saved clipboard items.")
        }
        .confirmationDialog("Delete All Ledge Data?", isPresented: $showDeleteAllConfirmation, titleVisibility: .visible) {
            Button("Delete All Ledge Data", role: .destructive) {
                do { try purger.deleteAll(); report = .empty; statusMessage = "Ledge data deleted. macOS permissions were unchanged." }
                catch { statusMessage = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The key is removed first; interrupted cleanup leaves remaining payloads unreadable until recovery cleanup succeeds.")
        }
    }

    private func byteString(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private static func liveRepository() throws -> SQLiteShelfStore {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ledge", isDirectory: true)
        return try SQLiteShelfStore(root: root, keyStore: KeychainMasterKeyStore(service: Bundle.main.bundleIdentifier ?? "com.ledge.app"))
    }

    private static func performClearExpired() {
        Task { try? await liveRepository().purgeExpired(before: .now) }
    }

    private static func performDeleteClipboardHistory() {
        Task {
            guard let repository = try? liveRepository(), let items = try? await repository.list(ShelfQuery()) else { return }
            for item in items where item.kind == .clipboardText || item.kind == .clipboardURL {
                try? await repository.delete(id: item.id)
            }
        }
    }
}
