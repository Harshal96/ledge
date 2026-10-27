import Foundation
import CryptoKit
import AutomationDomain

extension SQLiteAutomationStore {
    public func appInstallations() throws -> [PluginInstallation] {
        try db.rows("SELECT id,payload FROM app_installations").map { try open($0[1].data!, namespace: "app/install/\($0[0].string!)") }
    }
    public func installApp(_ installation: PluginInstallation) throws {
        guard try !appInstallations().contains(where: { $0.id == installation.id }) else { throw PlatformError.invalid("App is already installed; updates require explicit review") }
        try db.execute("INSERT INTO app_installations VALUES(?,?)", [.text(installation.id), .blob(try seal(installation, namespace: "app/install/\(installation.id)"))])
    }
    public func appInstances() throws -> [PluginInstance] {
        try db.rows("SELECT id,payload FROM app_instances").map { try open($0[1].data!, namespace: "app/instance/\($0[0].string!)") }
    }
    @discardableResult public func saveInstance(_ proposed: PluginInstance) throws -> PluginInstance {
        guard Validation.identifier(proposed.id), !proposed.name.isEmpty, proposed.name.count <= 100,
              try appInstallations().contains(where: { $0.id == proposed.installationID }) else { throw PlatformError.invalid("Instance needs an installed app and a name") }
        var instance = proposed
        if let old = try appInstances().first(where: { $0.id == instance.id }) {
            guard old.installationID == instance.installationID, old.revision == instance.revision else { throw PlatformError.invalid("Instance changed; reload before saving") }
            instance.revision += 1; instance.generation = old.generation + 1
        } else {
            // New ownership cannot attach to legacy jobs or retained data. A
            // restoration/migration requires its own explicit reviewed path.
            for (table, column) in [("jobs", "id"), ("app_archives", "id"), ("state", "job"), ("records", "job"), ("events", "job"), ("runs", "job")] {
                guard try db.rows("SELECT 1 FROM \(table) WHERE \(column)=? LIMIT 1", [.text(instance.id)]).isEmpty else { throw PlatformError.denied("Instance ID is reserved by existing or retained data; choose a new ID") }
            }
            instance.enabled = false; instance.revision = 1; instance.generation = 1
        }
        try db.transaction {
            try db.execute("DELETE FROM app_leases WHERE instance=?", [.text(instance.id)])
            try db.execute("DELETE FROM meta WHERE k=?", [.text("due/\(instance.id)")])
            try db.execute("INSERT INTO app_instances VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [.text(instance.id), .blob(try seal(instance, namespace: "app/instance/\(instance.id)"))])
        }
        return instance
    }
    public func removeApp(_ id: String, keepData: Bool) throws {
        let instances = try appInstances().filter { $0.installationID == id }
        guard try appInstallations().contains(where: { $0.id == id }) else { throw PlatformError.invalid("App is not installed") }
        try db.transaction {
            for instance in instances {
                if keepData { try db.execute("INSERT INTO app_archives VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [.text(instance.id), .blob(try seal(instance, namespace: "app/archive/\(instance.id)"))]) }
                try db.execute("DELETE FROM app_leases WHERE instance=?", [.text(instance.id)])
                try db.execute("DELETE FROM app_instances WHERE id=?", [.text(instance.id)])
                try db.execute("DELETE FROM meta WHERE k=?", [.text("due/\(instance.id)")])
                if !keepData {
                    for table in ["app_views", "app_checkpoints"] { try db.execute("DELETE FROM \(table) WHERE instance=?", [.text(instance.id)]) }
                    for table in ["state", "records", "events"] { try db.execute("DELETE FROM \(table) WHERE job=?", [.text(instance.id)]) }
                }
            }
            try db.execute("DELETE FROM app_installations WHERE id=?", [.text(id)])
        }
    }
    public func acquireAppLease(instanceID: String, expectedRevision: Int? = nil) throws -> PluginLease {
        guard try !isStopped(), let instance = try appInstances().first(where: { $0.id == instanceID }), instance.enabled,
              expectedRevision == nil || instance.revision == expectedRevision,
              try db.rows("SELECT id FROM app_leases WHERE instance=?", [.text(instanceID)]).isEmpty else { throw PlatformError.denied("App is disabled, stopped or already running") }
        let lease = PluginLease(instance: instance)
        try db.execute("INSERT INTO app_leases VALUES(?,?,?)", [.text(instanceID), .text(lease.id), .blob(try seal(lease, namespace: "app/lease/\(instanceID)"))])
        return lease
    }
    public func disableAppInstance(_ id: String) throws -> PluginInstance {
        guard var instance = try appInstances().first(where: { $0.id == id }) else { throw PlatformError.invalid("Instance not found") }
        instance.enabled = false
        return try saveInstance(instance)
    }
    public func validateAppLease(_ lease: PluginLease) throws -> PluginInstance {
        guard try !isStopped(), let instance = try appInstances().first(where: { $0.id == lease.instanceID }), instance.enabled,
              instance.installationID == lease.installationID, instance.generation == lease.generation, instance.revision == lease.revision,
              try db.rows("SELECT id FROM app_leases WHERE instance=?", [.text(instance.id)]).first?[0].string == lease.id else { throw PlatformError.denied("App lease was revoked") }
        return instance
    }
    public func releaseAppLease(_ lease: PluginLease) throws { try db.execute("DELETE FROM app_leases WHERE instance=? AND id=?", [.text(lease.instanceID), .text(lease.id)]) }
    public func recoverAppLeases() throws { try db.execute("DELETE FROM app_leases") }
    public func appView(instanceID: String) throws -> PluginViewSnapshot? {
        guard let row = try db.rows("SELECT payload FROM app_views WHERE instance=?", [.text(instanceID)]).first else { return nil }
        return try open(row[0].data!, namespace: "app/view/\(instanceID)")
    }
    public func appStateRevision(instanceID: String) throws -> Int {
        Int(try db.rows("SELECT v FROM meta WHERE k=?", [.text("app/revision/\(instanceID)")]).first?[0].string ?? "0") ?? 0
    }
    public func commitCheckpoint(lease: PluginLease, batch: ServiceCheckpoint) throws -> CommitReceipt {
        struct SavedReceipt: Codable { let digest: String; let receipt: CommitReceipt }
        let data = try WireCoding.encoder().encode(batch)
        guard data.count <= 262_144, Validation.identifier(batch.id), batch.sequence > 0 else { throw PlatformError.invalid("Invalid checkpoint") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var receipt: CommitReceipt!
        try db.transaction {
            try Task.checkCancellation()
            let instance = try validateAppLease(lease)
            let namespace = "app/receipt/\(instance.id)/\(batch.id)"
            if let row = try db.rows("SELECT payload FROM app_checkpoints WHERE instance=? AND id=?", [.text(instance.id), .text(batch.id)]).first {
                let saved: SavedReceipt = try open(row[0].data!, namespace: namespace)
                guard saved.digest == digest else { throw PlatformError.invalid("Checkpoint ID replayed with different contents") }
                receipt = saved.receipt; return
            }
            let revision = try appStateRevision(instanceID: instance.id)
            let sequenceKey = "app/sequence/\(lease.id)"
            let previousSequence = Int(try db.rows("SELECT v FROM meta WHERE k=?", [.text(sequenceKey)]).first?[0].string ?? "0") ?? 0
            guard batch.expectedStateRevision == revision, batch.sequence > previousSequence else { throw PlatformError.invalid("Stale checkpoint state or sequence") }
            guard let installation = try appInstallations().first(where: { $0.id == instance.installationID }) else { throw PlatformError.denied("App was uninstalled") }
            let result = batch.result
            if result.state != nil || !(result.recordMutations ?? []).isEmpty { guard installation.grants.contains("state.readwrite") else { throw PlatformError.denied("State access not granted") } }
            if !(result.events ?? []).isEmpty { guard installation.grants.contains("events.publish") else { throw PlatformError.denied("Event publication not granted") } }
            if let snapshot = result.viewSnapshot {
                guard installation.grants.contains("presentation.publish") else { throw PlatformError.denied("Presentation not granted") }
                try snapshot.presentation.validate(instanceID: instance.id)
                if let previous = try appView(instanceID: instance.id) { guard snapshot.presentation.revision > previous.presentation.revision else { throw PlatformError.invalid("Presentation revision must increase") } }
                try db.execute("INSERT INTO app_views VALUES(?,?) ON CONFLICT(instance) DO UPDATE SET payload=excluded.payload", [.text(instance.id), .blob(try seal(snapshot, namespace: "app/view/\(instance.id)"))])
            }
            // Reuse the exact transactional result validator/committer used by
            // successful command runs, without nesting another transaction.
            try writeAppResult(instanceID: instance.id, result: result.legacyResult)
            receipt = CommitReceipt(checkpointID: batch.id, stateRevision: revision + 1)
            try db.execute("INSERT INTO app_checkpoints VALUES(?,?,?)", [.text(instance.id), .text(batch.id), .blob(try seal(SavedReceipt(digest: digest, receipt: receipt), namespace: namespace))])
            for (key, value) in [("app/revision/\(instance.id)", String(revision + 1)), (sequenceKey, String(batch.sequence))] {
                try db.execute("INSERT INTO meta VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v", [.text(key), .text(value)])
            }
        }
        return receipt
    }
    private func writeAppResult(instanceID: String, result: RunResult) throws {
        guard result.events.count <= 100, (result.summary?.utf8.count ?? 0) <= 4096 else { throw PlatformError.invalid("Result exceeds limits") }
        if let state = result.state {
            guard try WireCoding.encoder().encode(state).count <= 65_536 else { throw PlatformError.invalid("State exceeds 64 KiB") }
            try db.execute("INSERT INTO state VALUES(?,?) ON CONFLICT(job) DO UPDATE SET payload=excluded.payload", [.text(instanceID), .blob(try seal(state, namespace: "state/\(instanceID)"))])
        }
        for record in result.recordMutations {
            guard Validation.identifier(record.collection), !record.key.isEmpty, record.key.utf8.count <= 256, try WireCoding.encoder().encode(record).count <= 16_384 else { throw PlatformError.invalid("Invalid app record") }
            let args: [AutomationDatabase.Value] = [.text(instanceID), .text(record.collection), .text(record.key)]
            if record.value == nil { try db.execute("DELETE FROM records WHERE job=? AND collection=? AND k=?", args) }
            else { try db.execute("INSERT INTO records VALUES(?,?,?,?) ON CONFLICT(job,collection,k) DO UPDATE SET payload=excluded.payload", args + [.blob(try seal(record, namespace: "record/\(instanceID)/\(record.collection)/\(record.key)"))]) }
        }
        let usage = try db.rows("SELECT count(*),coalesce(sum(length(payload)),0) FROM records WHERE job=?", [.text(instanceID)])[0]
        guard usage[0].int <= 50_000, usage[1].int <= 25 * 1024 * 1024 else { throw PlatformError.invalid("App record quota exhausted") }
        for event in result.events {
            _ = try HostEvent.validated(data: WireCoding.encoder().encode(event))
            let source = HMAC<SHA256>.authenticationCode(for: Data(event.sourceKey.utf8), using: key).map { String(format: "%02x", $0) }.joined()
            let old = try db.rows("SELECT id FROM events WHERE job=? AND source=?", [.text(instanceID), .text(source)]).first
            let id = old?[0].string ?? UUID().uuidString
            try db.execute("INSERT INTO events(id,job,source,revision,created,payload) VALUES(?,?,?,?,?,?) ON CONFLICT(job,source) DO UPDATE SET payload=excluded.payload,revision=excluded.revision", [.text(id), .text(instanceID), .text(source), .integer(Int64(event.revision)), .real(Date().timeIntervalSince1970), .blob(try seal(event, namespace: "event/\(id)"))])
        }
    }
}
