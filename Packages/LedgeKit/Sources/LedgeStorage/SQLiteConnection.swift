import Foundation
import SQLite3

final class SQLiteConnection: @unchecked Sendable {
    private var handle: OpaquePointer?
    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw PayloadVaultError.fileSystem }
        try execute("PRAGMA journal_mode=WAL"); try execute("PRAGMA foreign_keys=ON"); try execute("PRAGMA busy_timeout=5000")
    }
    deinit { sqlite3_close(handle) }
    func execute(_ sql: String) throws { guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw PayloadVaultError.fileSystem } }
    func transaction<T>(_ body: () throws -> T) throws -> T { try execute("BEGIN IMMEDIATE"); do { let value = try body(); try execute("COMMIT"); return value } catch { try? execute("ROLLBACK"); throw error } }
    func prepare(_ sql: String) throws -> OpaquePointer { var statement: OpaquePointer?; guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw PayloadVaultError.fileSystem }; return statement }
}
