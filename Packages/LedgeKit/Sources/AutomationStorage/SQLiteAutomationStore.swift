import Foundation
import CryptoKit
import SQLite3
import AutomationDomain

public actor SQLiteAutomationStore {
    private let db: AutomationDatabase
    private let key: SymmetricKey

    public init(root: URL, key: Data) throws {
        guard key.count == 32 else { throw PlatformError.invalid("Expected a 256-bit automation key") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        self.key = SymmetricKey(data: key)
        db = try AutomationDatabase(root.appendingPathComponent("automation.sqlite"))
        try db.execute("PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY,payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY,job TEXT NOT NULL,occurrence TEXT NOT NULL,status TEXT NOT NULL,payload BLOB NOT NULL, UNIQUE(job,occurrence)); CREATE TABLE IF NOT EXISTS state(job TEXT PRIMARY KEY,payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS records(job TEXT,collection TEXT,k TEXT,payload BLOB NOT NULL,PRIMARY KEY(job,collection,k)); CREATE TABLE IF NOT EXISTS events(id TEXT PRIMARY KEY,job TEXT NOT NULL,source TEXT NOT NULL,revision INTEGER NOT NULL,created REAL NOT NULL,unread INTEGER NOT NULL DEFAULT 1,delivered INTEGER NOT NULL DEFAULT 0,payload BLOB NOT NULL,UNIQUE(job,source)); CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY,v TEXT NOT NULL); PRAGMA user_version=1;")
    }

    public func apply(_ jobs: [AutomationDefinition]) throws {
        guard Set(jobs.map(\.id)).count == jobs.count else { throw PlatformError.invalid("Duplicate automation IDs") }
        try db.transaction {
            for var job in jobs {
                if let previous = try self.jobs().first(where: { $0.id == job.id }) {
                    job.revision = previous.revision + 1
                    for run in try history() where run.automationID == job.id && run.outcome == "running" {
                        try finish(run, outcome: "interrupted", summary: "Configuration changed before the run committed")
                    }
                    if job.plugin != previous.plugin || job.config != previous.config || job.connection != previous.connection {
                        try db.execute("DELETE FROM state WHERE job=?", [.text(job.id)])
                    }
                    // Same-plugin configuration edits must retain issue identities
                    // and notification tombstones. Account/plugin changes cannot
                    // expose the previous principal's records to a new program.
                    if job.plugin != previous.plugin || job.connection != previous.connection {
                        try db.execute("DELETE FROM records WHERE job=?", [.text(job.id)])
                    }
                    try db.execute("DELETE FROM meta WHERE k=?", [.text("due/\(job.id)")])
                }
                try db.execute("INSERT INTO jobs(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [.text(job.id), .blob(try seal(job, namespace: "job/\(job.id)"))])
            }
        }
    }
    public func jobs() throws -> [AutomationDefinition] { try db.rows("SELECT id,payload FROM jobs").map { try open($0[1].data!, namespace: "job/\($0[0].string!)") } }
    public func state(jobID: String) throws -> JSONValue {
        guard let row = try db.rows("SELECT payload FROM state WHERE job=?", [.text(jobID)]).first else { return .empty }
        return try open(row[0].data!, namespace: "state/\(jobID)")
    }
    public func records(jobID: String, collection: String, after: String = "", limit: Int = 100) throws -> [PluginRecord] {
        var bytes = 0
        return try db.rows("SELECT k,payload FROM records WHERE job=? AND collection=? AND k>? ORDER BY k LIMIT ?", [.text(jobID), .text(collection), .text(after), .integer(Int64(min(100, max(1, limit))))]).compactMap { row in
            let record: PluginRecord = try open(row[1].data!, namespace: "record/\(jobID)/\(collection)/\(row[0].string!)")
            bytes += try WireCoding.encoder().encode(record).count
            return bytes <= 131_072 ? record : nil
        }
    }
    public func claim(jobID: String, occurrence: String, now: Date) throws -> String? {
        var lease: String?
        try db.transaction {
            guard try db.rows("SELECT id FROM runs WHERE job=? AND (occurrence=? OR status='running')", [.text(jobID), .text(occurrence)]).isEmpty else { return }
            let id = UUID().uuidString
            let run = RunRecord(id: id, automationID: jobID, occurrence: occurrence, startedAt: now)
            try db.execute("INSERT INTO runs(id,job,occurrence,status,payload) VALUES(?,?,?,'running',?)", [.text(id), .text(jobID), .text(occurrence), .blob(try seal(run, namespace: "run/\(id)"))]); lease = id
        }
        return lease
    }
    public func complete(_ lease: String, result: RunResult) throws {
        guard result.events.count <= 100, try WireCoding.encoder().encode(result).count <= 262_144 else { throw PlatformError.invalid("Result exceeds protocol budget") }
        guard (result.summary?.utf8.count ?? 0) <= 4096 else { throw PlatformError.invalid("Run summary exceeds 4 KiB") }
        if let state = result.state, try WireCoding.encoder().encode(state).count > 65_536 { throw PlatformError.invalid("State exceeds 64 KiB") }
        for event in result.events { _ = try HostEvent.validated(data: WireCoding.encoder().encode(event)) }
        for record in result.recordMutations {
            guard Validation.identifier(record.collection), !record.key.isEmpty, record.key.utf8.count <= 256, try WireCoding.encoder().encode(record).count <= 16_384 else { throw PlatformError.invalid("Invalid plugin record") }
        }
        try db.transaction {
            try Task.checkCancellation()
            guard try !isStopped() else { throw PlatformError.cancelled }
            let run = try running(lease)
            if let state = result.state { try db.execute("INSERT INTO state(job,payload) VALUES(?,?) ON CONFLICT(job) DO UPDATE SET payload=excluded.payload", [.text(run.automationID), .blob(try seal(state, namespace: "state/\(run.automationID)"))]) }
            for record in result.recordMutations {
                let args: [AutomationDatabase.Value] = [.text(run.automationID), .text(record.collection), .text(record.key)]
                if record.value == nil { try db.execute("DELETE FROM records WHERE job=? AND collection=? AND k=?", args) }
                else { try db.execute("INSERT INTO records(job,collection,k,payload) VALUES(?,?,?,?) ON CONFLICT(job,collection,k) DO UPDATE SET payload=excluded.payload", args + [.blob(try seal(record, namespace: "record/\(run.automationID)/\(record.collection)/\(record.key)"))]) }
            }
            let usage = try db.rows("SELECT count(*),coalesce(sum(length(payload)),0) FROM records WHERE job=?", [.text(run.automationID)])[0]
            guard usage[0].int <= 50_000, usage[1].int <= 25 * 1024 * 1024 else { throw PlatformError.invalid("Plugin record quota exhausted") }
            for event in result.events {
                let source = HMAC<SHA256>.authenticationCode(for: Data(event.sourceKey.utf8), using: key).map { String(format: "%02x", $0) }.joined()
                let existing = try db.rows("SELECT id FROM events WHERE job=? AND source=?", [.text(run.automationID), .text(source)]).first
                let id = existing?[0].string ?? UUID().uuidString
                try db.execute("INSERT INTO events(id,job,source,revision,created,payload) VALUES(?,?,?,?,?,?) ON CONFLICT(job,source) DO UPDATE SET payload=excluded.payload,revision=excluded.revision", [.text(id), .text(run.automationID), .text(source), .integer(Int64(event.revision)), .real(Date().timeIntervalSince1970), .blob(try seal(event, namespace: "event/\(id)"))])
            }
            try finish(run, outcome: "succeeded", summary: result.summary)
        }
    }
    public func fail(_ lease: String, outcome: String, summary: String? = nil) throws { try finish(running(lease), outcome: outcome, summary: summary) }
    public func recoverInterrupted() throws {
        let runs = try history().filter { $0.outcome == "running" }
        for run in runs { try finish(run, outcome: "interrupted", summary: "Runner stopped before committing; run manually to retry.") }
    }
    public func history() throws -> [RunRecord] { try db.rows("SELECT id,payload FROM runs ORDER BY rowid DESC LIMIT 1000").map { try open($0[1].data!, namespace: "run/\($0[0].string!)") } }
    public func inbox() throws -> [InboxEvent] {
        try db.rows("SELECT id,job,payload,created,unread FROM events ORDER BY created DESC LIMIT 1000").map { row in
            InboxEvent(id: row[0].string!, automationID: row[1].string!, event: try open(row[2].data!, namespace: "event/\(row[0].string!)"), createdAt: Date(timeIntervalSince1970: row[3].double), unread: row[4].int != 0)
        }
    }
    public func acknowledge(_ id: String) throws { try db.execute("UPDATE events SET unread=0,delivered=1 WHERE id=?", [.text(id)]) }
    public func pendingDeliveryIDs() throws -> [String] { try db.rows("SELECT id FROM events WHERE delivered=0 ORDER BY created").compactMap { $0[0].string } }
    public func delivered(_ id: String) throws { try db.execute("UPDATE events SET delivered=1 WHERE id=?", [.text(id)]) }
    public func setStopped(_ stopped: Bool) throws { try db.execute("INSERT INTO meta(k,v) VALUES('stopped',?) ON CONFLICT(k) DO UPDATE SET v=excluded.v", [.text(stopped ? "1" : "0")]) }
    public func isStopped() throws -> Bool { try db.rows("SELECT v FROM meta WHERE k='stopped'").first?[0].string == "1" }
    public func setNextDue(jobID: String, date: Date) throws { try db.execute("INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v", [.text("due/\(jobID)"), .text(String(date.timeIntervalSince1970))]) }
    public func nextDue(jobID: String) throws -> Date? { try db.rows("SELECT v FROM meta WHERE k=?", [.text("due/\(jobID)")]).first?[0].string.flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) }

    private func running(_ id: String) throws -> RunRecord {
        guard let row = try db.rows("SELECT payload FROM runs WHERE id=? AND status='running'", [.text(id)]).first else { throw PlatformError.invalid("Run lease is no longer active") }
        return try open(row[0].data!, namespace: "run/\(id)")
    }
    private func finish(_ run: RunRecord, outcome: String, summary: String?) throws {
        let value = RunRecord(id: run.id, automationID: run.automationID, occurrence: run.occurrence, startedAt: run.startedAt, finishedAt: .now, outcome: outcome, summary: summary)
        try db.execute("UPDATE runs SET status=?,payload=? WHERE id=? AND status='running'", [.text(outcome), .blob(try seal(value, namespace: "run/\(run.id)")), .text(run.id)])
    }
    private func seal<T: Encodable>(_ value: T, namespace: String) throws -> Data { try AES.GCM.seal(WireCoding.encoder().encode(value), using: key, authenticating: Data(namespace.utf8)).combined! }
    private func open<T: Decodable>(_ data: Data, namespace: String) throws -> T { try WireCoding.decoder().decode(T.self, from: AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: Data(namespace.utf8))) }
}

private final class AutomationDatabase: @unchecked Sendable {
    enum Value {
        case text(String), blob(Data), integer(Int64), real(Double), null
        var string: String? { if case let .text(v) = self { return v }; return nil }
        var data: Data? { if case let .blob(v) = self { return v }; return nil }
        var int: Int64 { if case let .integer(v) = self { return v }; return 0 }
        var double: Double { if case let .real(v) = self { return v }; return Double(int) }
    }
    private let handle: OpaquePointer
    init(_ url: URL) throws {
        var h: OpaquePointer?
        guard sqlite3_open_v2(url.path, &h, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let h else { throw PlatformError.unavailable("Cannot open automation database") }
        handle = h
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    deinit { sqlite3_close(handle) }
    func transaction(_ body: () throws -> Void) throws { try execute("BEGIN IMMEDIATE"); do { try body(); try execute("COMMIT") } catch { try? execute("ROLLBACK"); throw error } }
    func execute(_ sql: String, _ args: [Value] = []) throws {
        if args.isEmpty { guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }; return }
        let s = try prepare(sql, args); defer { sqlite3_finalize(s) }; guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
    }
    func rows(_ sql: String, _ args: [Value] = []) throws -> [[Value]] {
        let s = try prepare(sql, args); defer { sqlite3_finalize(s) }; var rows: [[Value]] = []
        while true {
            let status = sqlite3_step(s); if status == SQLITE_DONE { break }; guard status == SQLITE_ROW else { throw failure() }
            rows.append((0..<sqlite3_column_count(s)).map { column in
                switch sqlite3_column_type(s, column) {
                case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(s, column)))
                case SQLITE_BLOB: let size = Int(sqlite3_column_bytes(s, column)); return .blob(size == 0 ? Data() : Data(bytes: sqlite3_column_blob(s, column)!, count: size))
                case SQLITE_INTEGER: return .integer(sqlite3_column_int64(s, column))
                case SQLITE_FLOAT: return .real(sqlite3_column_double(s, column))
                default: return .null
                }
            })
        }; return rows
    }
    private func prepare(_ sql: String, _ args: [Value]) throws -> OpaquePointer {
        var s: OpaquePointer?; guard sqlite3_prepare_v2(handle, sql, -1, &s, nil) == SQLITE_OK, let s else { throw failure() }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in args.enumerated() {
            let i = Int32(offset + 1)
            switch value {
            case let .text(v): sqlite3_bind_text(s, i, v, -1, transient)
            case let .blob(v): _ = v.withUnsafeBytes { sqlite3_bind_blob(s, i, $0.baseAddress, Int32(v.count), transient) }
            case let .integer(v): sqlite3_bind_int64(s, i, v)
            case let .real(v): sqlite3_bind_double(s, i, v)
            case .null: sqlite3_bind_null(s, i)
            }
        }; return s
    }
    private func failure() -> PlatformError { .unavailable("Automation database error: \(String(cString: sqlite3_errmsg(handle)))") }
}
