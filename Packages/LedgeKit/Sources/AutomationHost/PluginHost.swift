import Foundation
import AutomationDomain
import AutomationStorage
import AutomationRuntime
import PluginRuntime

/// Feature-independent v2 app orchestration. A catalog is GUI metadata; only
/// an explicit installation and enabled instance can reach this runner.
public actor PluginHost {
    public let store: SQLiteAutomationStore
    private let registry: PluginRegistry
    private let runner = ProgramRunner()
    private var tasks: [String: Task<Void, Never>] = [:]
    private var scheduler: Task<Void, Never>?
    private var generation = 0
    private var controlEpoch = 0
    private var errors: [String: String] = [:]
    private var watchers: [UUID: CheckedContinuation<Void, Never>] = [:]
    private func changed() {
        generation += 1
        let pending = Array(watchers.values); watchers.removeAll(); pending.forEach { $0.resume() }
    }
    private func expire(_ id: UUID) { watchers.removeValue(forKey: id)?.resume() }
    public typealias IntegrationCall = @Sendable (PluginInstance, PluginInstallation, String, JSONValue) async throws -> JSONValue
    private let integration: IntegrationCall?
    public init(store: SQLiteAutomationStore, registry: PluginRegistry, integration: IntegrationCall? = nil) { self.store = store; self.registry = registry; self.integration = integration }

    public func handle(_ method: String, params: JSONValue = .empty) async throws -> JSONValue {
        switch method {
        case "apps.watch":
            guard let previous = Int(exactly: params["generation"].number ?? -1) else { throw PlatformError.invalid("Invalid watch generation") }
            if previous == generation {
                await withCheckedContinuation { continuation in
                    let id = UUID(); watchers[id] = continuation
                    Task { try? await Task.sleep(for: .seconds(20)); self.expire(id) }
                }
            }
            return try await handle("apps.snapshot")
        case "apps.snapshot":
            let instances = try await store.appInstances()
            let enabled = Set(instances.filter(\.enabled).map(\.id))
            let events = try await store.inbox().filter { enabled.contains($0.automationID) }.prefix(50)
            var views: [String: JSONValue] = [:]
            for instance in instances where instance.enabled { if let view = try await store.appView(instanceID: instance.id) { views[instance.id] = try WireCoding.value(view) } }
            return .object(["generation": .number(Double(generation)), "installations": try WireCoding.value(await store.appInstallations()), "instances": try WireCoding.value(instances), "views": .object(views), "events": try WireCoding.value(Array(events)), "pendingDelivery": .array(try await store.pendingDeliveryIDs().map(JSONValue.string)), "errors": .object(errors.mapValues(JSONValue.string)), "running": .array(tasks.keys.map(JSONValue.string)), "stopped": .bool(try await store.isStopped())])
        case "apps.install":
            guard let path = params["path"].string else { throw PlatformError.invalid("App folder required") }
            let installation = try await registry.installApp(directory: URL(fileURLWithPath: path), trustLocalCode: params["trust"].bool == true, interpreter: params["interpreter"].string)
            try await store.installApp(installation); changed()
            return try WireCoding.value(installation)
        case "apps.save":
            let instance = try WireCoding.decoder().decode(PluginInstance.self, from: WireCoding.encoder().encode(params))
            if !instance.enabled, try await store.appInstances().contains(where: { $0.id == instance.id && $0.enabled }) {
                controlEpoch += 1; tasks[instance.id]?.cancel()
                let saved = try await store.disableAppInstance(instance.id); changed()
                return try WireCoding.value(saved)
            }
            guard let app = try await store.appInstallations().first(where: { $0.id == instance.installationID }) else { throw PlatformError.invalid("Install this app first") }
            try await registry.verifyApp(app)
            if let path = app.manifest.configSchema { try PluginConfigSchema.validate(instance.config, schema: StrictJSON.decode(Data(contentsOf: app.directory.appendingPathComponent(path)))) }
            try ScheduleEvaluator.validate(instance.schedule)
            guard TimeZone(identifier: instance.schedule.timezone) != nil, (0...60).contains(instance.schedule.jitterSeconds), ["skip", "run-latest"].contains(instance.schedule.misfire) else { throw PlatformError.invalid("Invalid schedule") }
            guard app.manifest.runtime.kind == "command" || !instance.enabled else { throw PlatformError.unavailable("Service apps are not yet supported by this runner") }
            if instance.enabled && (instance.schedule.cron != nil || instance.schedule.intervalSeconds != nil), app.manifest.commands.first(where: { $0.id == app.manifest.defaultCommand })?.destructive == true { throw PlatformError.denied("Destructive default commands must be run manually with confirmation") }
            controlEpoch += 1; tasks[instance.id]?.cancel()
            let saved = try await store.saveInstance(instance); changed(); startScheduler()
            return try WireCoding.value(saved)
        case "apps.disable":
            guard let id = params["id"].string else { throw PlatformError.invalid("Instance ID required") }
            controlEpoch += 1; tasks[id]?.cancel()
            let saved = try await store.disableAppInstance(id); changed()
            return try WireCoding.value(saved)
        case "apps.remove":
            guard let id = params["id"].string else { throw PlatformError.invalid("App ID required") }
            controlEpoch += 1
            for instance in try await store.appInstances() where instance.installationID == id { tasks[instance.id]?.cancel() }
            try await store.removeApp(id, keepData: params["keepData"].bool != false); changed()
            return .bool(true)
        case "apps.run":
            let action = try WireCoding.decoder().decode(PluginActionRequest.self, from: WireCoding.encoder().encode(params))
            return try await invoke(action)
        case "apps.eventURL":
            guard let id = params["instanceID"].string,
                  let instance = try await store.appInstances().first(where: { $0.id == id }), instance.enabled,
                  params["expectedRevision"].number == Double(instance.revision),
                  let event = try await store.inbox().first(where: { $0.id == params["eventID"].string && $0.automationID == id }),
                  let action = event.event.actions.first(where: { $0.id == params["actionID"].string }),
                  action.command == nil, let destination = action.url,
                  let url = URLComponents(string: destination), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
                  let installation = try await store.appInstallations().first(where: { $0.id == instance.installationID }) else { throw PlatformError.denied("This app link is no longer available") }
            try await registry.verifyApp(installation)
            // No worker-supplied URL is opened automatically. The GUI requests
            // this current, owned action only after an explicit user click.
            return .string(destination)
        default: throw PlatformError.denied("Unknown app operation")
        }
    }
    public func invoke(_ action: PluginActionRequest) async throws -> JSONValue {
        let epoch = controlEpoch
        guard tasks.count < 2, tasks[action.instanceID] == nil else { throw PlatformError.unavailable("App runner busy") }
        guard let instance = try await store.appInstances().first(where: { $0.id == action.instanceID }), instance.enabled, instance.revision == action.expectedRevision,
              let installation = try await store.appInstallations().first(where: { $0.id == instance.installationID }) else { throw PlatformError.denied("App is disabled, changed or uninstalled") }
        try installation.manifest.validateInvocation(action.command, arguments: action.arguments, confirmed: action.confirmed == true)
        if let revision = action.viewRevision { guard try await store.appView(instanceID: instance.id)?.presentation.revision == revision else { throw PlatformError.denied("View changed; reopen the app before acting") } }
        try await registry.verifyApp(installation)
        let lease = try await store.acquireAppLease(instanceID: instance.id, expectedRevision: instance.revision)
        guard epoch == controlEpoch, tasks.count < 2, tasks[instance.id] == nil else { try? await store.releaseAppLease(lease); throw PlatformError.cancelled }
        tasks[instance.id] = Task {
            await execute(instance: instance, installation: installation, lease: lease, action: action)
            self.tasks.removeValue(forKey: instance.id); self.changed()
        }
        changed()
        return .object(["accepted": .bool(true), "runID": .string(lease.id)])
    }
    private func execute(instance: PluginInstance, installation: PluginInstallation, lease: PluginLease, action: PluginActionRequest) async {
        var run: String?
        do {
            try Task.checkCancellation()
            _ = try await store.validateAppLease(lease)
            run = try await store.claim(jobID: instance.id, occurrence: "app/\(lease.id)", now: .now)
            let state = try await store.state(jobID: instance.id)
            let stateRevision = try await store.appStateRevision(instanceID: instance.id)
            let request: JSONValue = .object(["hostProtocol": .string("2"), "runID": .string(lease.id), "automationID": .string(instance.id), "command": .string(action.command), "arguments": action.arguments, "mode": .string("live"), "now": .string(ISO8601DateFormatter().string(from: Date())), "config": instance.config, "state": state, "stateRevision": .number(Double(stateRevision))])
            let broker = integration
            let storage = store
            let result = try await runner.execute(executable: installation.executable, arguments: installation.arguments, directory: installation.directory, request: request, timeout: 120, runID: lease.id) { method, params in
                _ = try await storage.validateAppLease(lease)
                switch method {
                case "host.state.get":
                    guard installation.grants.contains("state.readwrite") else { throw PlatformError.denied("State access not granted") }
                    return try await storage.state(jobID: instance.id)
                case "host.records.query":
                    guard installation.grants.contains("state.readwrite"), let collection = params["collection"].string else { throw PlatformError.denied("Record access not granted") }
                    return try WireCoding.value(await storage.records(jobID: instance.id, collection: collection, after: params["after"].string ?? ""))
                case "host.integration.call":
                    guard let broker else { throw PlatformError.unavailable("No connection provider is available") }
                    return try await broker(instance, installation, params["operation"].string ?? "", params["params"])
                case "host.log": return .bool(true)
                default: throw PlatformError.denied("Unsupported app host call")
                }
            }
            try Task.checkCancellation()
            let batch = ServiceCheckpoint(id: lease.id, sequence: 1, expectedStateRevision: stateRevision, result: .init(events: result.events, state: result.state, recordMutations: result.recordMutations, summary: result.summary, viewSnapshot: result.viewSnapshot))
            _ = try await store.commitCheckpoint(lease: lease, batch: batch)
            if let run { try await store.fail(run, outcome: "succeeded", summary: result.summary) }
            errors.removeValue(forKey: instance.id)
        } catch {
            errors[instance.id] = error.localizedDescription
            if let run { try? await store.fail(run, outcome: Task.isCancelled ? "cancelled" : "failed", summary: error.localizedDescription) }
        }
        try? await store.releaseAppLease(lease)
    }
    public func stop() async {
        controlEpoch += 1
        scheduler?.cancel(); tasks.values.forEach { $0.cancel() }; runner.cancelAll()
        try? await store.setStopped(true); changed()
    }
    public func startScheduler() {
        scheduler?.cancel()
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.tick()
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }
    private func tick() async -> Double {
        do {
            guard try await !store.isStopped() else { return 600 }
            let now = Date(); var next = now.addingTimeInterval(600)
            for instance in try await store.appInstances() where instance.enabled {
                guard let due = try await store.nextDue(jobID: instance.id) ?? ScheduleEvaluator.next(instance.schedule, after: now) else { continue }
                let execution = ScheduleEvaluator.executionDate(instance.schedule, due: due, identity: "\(instance.id)/\(instance.revision)")
                guard !Task.isCancelled else { return 600 }
                if execution <= now {
                    if ScheduleEvaluator.shouldRun(instance.schedule, due: execution, now: now) {
                        guard tasks[instance.id] == nil, tasks.count < 2 else { next = min(next, now.addingTimeInterval(1)); continue }
                        if let app = try await store.appInstallations().first(where: { $0.id == instance.installationID }) { _ = try await invoke(.init(instanceID: instance.id, command: app.manifest.defaultCommand, expectedRevision: instance.revision)) }
                    }
                    if let date = try ScheduleEvaluator.nextAfterOccurrence(instance.schedule, due: due, now: now) { try await store.setNextDue(jobID: instance.id, date: date); next = min(next, date) }
                } else { try await store.setNextDue(jobID: instance.id, date: due); next = min(next, execution) }
            }
            return max(1, next.timeIntervalSince(now))
        } catch { return 60 }
    }
}
