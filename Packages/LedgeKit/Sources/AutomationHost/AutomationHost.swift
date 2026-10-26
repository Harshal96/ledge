import Foundation
import AutomationDomain
import AutomationStorage
import AutomationRuntime
import PluginRuntime
import IntegrationKit
import GitHubIntegration

/// The agent alone owns this composition root. GUI and CLI use the same XPC
/// commands; plugins get only the scoped per-run channel below.
public actor AutomationHost {
    public let store: SQLiteAutomationStore
    public let registry: PluginRegistry
    private let credentials: CredentialStore
    private let github: GitHubProvider
    private let runner = ProgramRunner()
    private var scheduledTask: Task<Void, Never>?
    private var running = Set<String>()
    private var generation = 0
    private var failures: [String: Int] = [:]
    private var watchers: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var invocationTasks: [UUID: Task<Void, Never>] = [:]
    private var controlEpoch = 0

    private func cancelInvocations() {
        controlEpoch += 1
        invocationTasks.values.forEach { $0.cancel() }
        runner.cancelAll()
    }
    private func enqueue(_ job: AutomationDefinition, occurrence: String, dryRun: Bool) {
        let id = UUID(), epoch = controlEpoch
        invocationTasks[id] = Task {
            if epoch == self.controlEpoch && !Task.isCancelled {
                await self.execute(job, occurrence: occurrence, dryRun: dryRun)
            }
            self.invocationTasks.removeValue(forKey: id)
        }
    }

    private func changed() {
        generation += 1
        let pending = Array(watchers.values); watchers.removeAll()
        pending.forEach { $0.resume() }
    }
    private func expireWatcher(_ id: UUID) { watchers.removeValue(forKey: id)?.resume() }

    public static func open(root: URL? = nil) async throws -> AutomationHost {
        let path = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ledge/Automation", isDirectory: true)
        let credentials = CredentialStore()
        let exists = FileManager.default.fileExists(atPath: path.appendingPathComponent("automation.sqlite").path)
        let key = try await credentials.masterKey(allowCreation: !exists)
        let store = try SQLiteAutomationStore(root: path, key: key)
        let registry = try PluginRegistry(root: path.appendingPathComponent("Plugins", isDirectory: true))
        let host = AutomationHost(store: store, registry: registry, credentials: credentials)
        try await store.recoverInterrupted()
        await host.startScheduler()
        return host
    }
    public init(store: SQLiteAutomationStore, registry: PluginRegistry, credentials: CredentialStore) { self.store = store; self.registry = registry; self.credentials = credentials; github = GitHubProvider(credentials: credentials) }

    public func handle(_ method: String, params: JSONValue) async throws -> JSONValue {
        switch method {
        case "status", "snapshot": return try await snapshot()
        case "watch":
            guard let previous = Int(exactly: params["generation"].number ?? -1) else { throw PlatformError.invalid("Invalid watch generation") }
            if generation == previous {
                await withCheckedContinuation { continuation in
                    let id = UUID(); watchers[id] = continuation
                    Task { try? await Task.sleep(for: .seconds(20)); self.expireWatcher(id) }
                }
            }
            return try await snapshot()
        case "plugins": return try WireCoding.value(await registry.list())
        case "install":
            guard let path = params["path"].string else { throw PlatformError.invalid("Plugin path required") }
            let plugin = try await registry.install(directory: URL(fileURLWithPath: path), trustLocalCode: params["trust"].bool == true, interpreter: params["interpreter"].string)
            changed(); return try WireCoding.value(plugin)
        case "apply":
            let jobs = try ConfigurationValidator.validate(data: WireCoding.encoder().encode(params))
            for job in jobs {
                let plugin = try await registry.resolve(job.plugin)
                guard plugin.manifest.commands.contains(job.command) else { throw PlatformError.invalid("Plugin does not declare command '\(job.command)'") }
                if let schema = plugin.manifest.configSchema {
                    try PluginConfigSchema.validate(job.config, schema: StrictJSON.decode(Data(contentsOf: plugin.directory.appendingPathComponent(schema))))
                }
                try ScheduleEvaluator.validate(job.schedule)
            }
            scheduledTask?.cancel()
            cancelInvocations()
            try await store.apply(jobs); changed(); startScheduler(); return .object(["applied": .number(Double(jobs.count))])
        case "run":
            let epoch = controlEpoch
            guard try await !store.isStopped() else { throw PlatformError.denied("Automations are stopped; resume before running") }
            guard let id = params["id"].string, var job = try await store.jobs().first(where: { $0.id == id }) else { throw PlatformError.invalid("Automation not found") }
            if let command = params["command"].string {
                let plugin = try await registry.resolve(job.plugin)
                guard plugin.manifest.commands.contains(command) else { throw PlatformError.denied("Undeclared plugin command") }
                job.command = command
            }
            let requestID = UUID().uuidString
            guard epoch == controlEpoch else { throw PlatformError.cancelled }
            guard invocationTasks.count < 2, !running.contains(job.id) else { throw PlatformError.unavailable("Runner busy; retry after the current invocation completes") }
            enqueue(job, occurrence: "manual/\(requestID)", dryRun: params["dryRun"].bool == true)
            return .object(["accepted": .bool(true), "requestID": .string(requestID)])
        case "stop": cancelInvocations(); scheduledTask?.cancel(); try await store.setStopped(true); changed(); return .bool(true)
        case "resume": try await store.setStopped(false); failures.removeAll(); startScheduler(); changed(); return .bool(true)
        case "ack": if let id = params["id"].string { try await store.acknowledge(id) }; changed(); return .bool(true)
        case "delivered": if let id = params["id"].string { try await store.delivered(id) }; return .bool(true)
        case "connect.github":
            guard let name = params["name"].string, Validation.identifier(name), let token = params["token"].string, !token.isEmpty else { throw PlatformError.invalid("Connection name and token required") }
            let identity = try await github.verify(token: token)
            try await credentials.write(Data(token.utf8), name: "github/\(name)")
            changed(); return .object(["login": identity["login"], "connected": .bool(true)])
        case "disconnect.github":
            guard let name = params["name"].string, Validation.identifier(name) else { throw PlatformError.invalid("Connection name required") }
            try await credentials.delete("github/\(name)"); changed(); return .bool(true)
        default: throw PlatformError.denied("Unknown control operation")
        }
    }
    private func snapshot() async throws -> JSONValue {
        .object(["generation": .number(Double(generation)), "jobs": try WireCoding.value(await store.jobs()), "events": try WireCoding.value(Array(await store.inbox().prefix(50))), "runs": try WireCoding.value(Array(await store.history().prefix(50))), "stopped": .bool(try await store.isStopped()), "running": .number(Double(running.count)), "pendingDelivery": .array(try await store.pendingDeliveryIDs().prefix(50).map(JSONValue.string))])
    }
    public func startScheduler() {
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.tick(now: .now)
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }
    private func tick(now: Date) async -> Double {
        do {
            guard try await !store.isStopped() else { return 600 }
            var next = now.addingTimeInterval(600)
            for job in try await store.jobs() where job.enabled {
                guard failures[job.id, default: 0] < 3 else { continue }
                let due = try await store.nextDue(jobID: job.id) ?? ScheduleEvaluator.next(job.schedule, after: now)
                guard let due else { continue }
                let execution = ScheduleEvaluator.executionDate(job.schedule, due: due, identity: "\(job.id)/\(job.revision)")
                guard !Task.isCancelled else { return 600 }
                if execution <= now {
                    if ScheduleEvaluator.shouldRun(job.schedule, due: execution, now: now) {
                        guard !running.contains(job.id), invocationTasks.count < 2 else { next = min(next, now.addingTimeInterval(1)); continue }
                        let occurrence = "\(job.revision)/\(Int(due.timeIntervalSince1970))"
                        enqueue(job, occurrence: occurrence, dryRun: false)
                    }
                    if let upcoming = try ScheduleEvaluator.nextAfterOccurrence(job.schedule, due: due, now: now) { try await store.setNextDue(jobID: job.id, date: upcoming); next = min(next, upcoming) }
                } else { try await store.setNextDue(jobID: job.id, date: due); next = min(next, execution) }
            }
            return max(1, next.timeIntervalSince(now))
        } catch { return 60 }
    }
    private func execute(_ job: AutomationDefinition, occurrence: String, dryRun: Bool) async {
        guard !running.contains(job.id), running.count < 2 else { return }
        running.insert(job.id); changed()
        defer { running.remove(job.id); changed() }
        var lease: String?
        do {
            try Task.checkCancellation()
            guard let claimed = try await store.claim(jobID: job.id, occurrence: occurrence, now: .now) else { return }; lease = claimed
            let plugin = try await registry.resolve(job.plugin)
            let context = RunContext(job: job, plugin: plugin.manifest, store: store, github: github)
            let request: JSONValue = .object(["runID": .string(claimed), "automationID": .string(job.id), "command": .string(job.command), "config": job.config, "state": try await store.state(jobID: job.id), "mode": .string(dryRun ? "dryRun" : "live"), "now": .string(ISO8601DateFormatter().string(from: Date())), "hostProtocol": .string("1")])
            try Task.checkCancellation()
            let result = try await runner.execute(executable: plugin.executable, arguments: plugin.arguments, directory: plugin.directory, request: request, timeout: Double(job.timeoutSeconds), runID: claimed) { method, params in try await context.call(method, params: params) }
            try Task.checkCancellation()
            if dryRun { try await store.fail(claimed, outcome: "preview", summary: result.summary) }
            else {
                if !result.events.isEmpty && !plugin.manifest.capabilities.contains("events.publish") { throw PlatformError.denied("Plugin has no events.publish grant") }
                if (result.state != nil || !result.recordMutations.isEmpty) && !plugin.manifest.capabilities.contains("state.readwrite") { throw PlatformError.denied("Plugin has no state.readwrite grant") }
                try await store.complete(claimed, result: result)
            }
            failures[job.id] = 0
        } catch {
            failures[job.id, default: 0] += 1
            if let lease { try? await store.fail(lease, outcome: "failed", summary: error.localizedDescription) }
        }
    }
}

private actor RunContext {
    let job: AutomationDefinition; let plugin: PluginManifest; let store: SQLiteAutomationStore; let github: GitHubProvider
    private var requests = 0
    init(job: AutomationDefinition, plugin: PluginManifest, store: SQLiteAutomationStore, github: GitHubProvider) { self.job = job; self.plugin = plugin; self.store = store; self.github = github }
    func call(_ method: String, params: JSONValue) async throws -> JSONValue {
        switch method {
        case "host.state.get": guard plugin.capabilities.contains("state.readwrite") else { throw PlatformError.denied("State access not granted") }; return try await store.state(jobID: job.id)
        case "host.records.query":
            guard plugin.capabilities.contains("state.readwrite"), let collection = params["collection"].string else { throw PlatformError.denied("Record access not granted") }
            return try WireCoding.value(await store.records(jobID: job.id, collection: collection, after: params["after"].string ?? ""))
        case "host.integration.call":
            requests += 1; guard requests <= 120 else { throw PlatformError.unavailable("Per-run integration budget exhausted; resume next scan") }
            let operation = params["operation"].string ?? ""
            let capability = operation.hasPrefix("github.pullRequests.") ? "github.pullRequests.read" : "github.issues.read"
            guard plugin.capabilities.contains(capability), let connection = job.connection else { throw PlatformError.denied("GitHub connection/capability not granted") }
            let repositories = job.config["repositories"].array?.compactMap(\.string) ?? []
            return try await github.call(operation: operation, parameters: params["params"], account: connection, repositories: repositories)
        case "host.log": return .bool(true) // arbitrary text is not persisted as potentially sensitive telemetry
        default: throw PlatformError.denied("Unsupported plugin host method")
        }
    }
}
