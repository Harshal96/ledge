import Foundation

enum ShelfMigration {
    static func apply(to connection: SQLiteConnection) throws {
        try connection.transaction {
            try connection.execute("CREATE TABLE IF NOT EXISTS shelf_item (id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL, created_at REAL NOT NULL, expires_at REAL, is_favorite INTEGER NOT NULL CHECK (is_favorite IN (0, 1)), state TEXT NOT NULL CHECK (state IN ('importing', 'ready', 'deleting')), payload_path TEXT NOT NULL UNIQUE, payload_bytes INTEGER NOT NULL CHECK (payload_bytes >= 0), keyed_digest BLOB NOT NULL)")
            try connection.execute("CREATE TABLE IF NOT EXISTS storage_operation (id TEXT PRIMARY KEY NOT NULL, item_id TEXT NOT NULL, operation TEXT NOT NULL CHECK (operation IN ('import', 'export', 'delete')), stage TEXT NOT NULL, created_at REAL NOT NULL, FOREIGN KEY (item_id) REFERENCES shelf_item(id) ON DELETE CASCADE)")
            try connection.execute("PRAGMA user_version=1")
        }
    }
}
