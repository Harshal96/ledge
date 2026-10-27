import Foundation
import AppKit
import Observation
import ServiceManagement
import AutomationDomain
import AgentIPC
import NotificationRouting

public struct AppCatalogEntry: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    public var icon: String
    public var folder: String
    public var category: String
}

@MainActor @Observable public final class AppLibraryStore {
    public static let shared = AppLibraryStore()
    public private(set) var catalog: [AppCatalogEntry] = []
    public private(set) var installations: [PluginInstallation] = []
    public private(set) var instances: [PluginInstance] = []
    public private(set) var views: [String: PluginViewSnapshot] = [:]
    public private(set) var errors: [String: String] = [:]
    public private(set) var running: Set<String> = []
    public private(set) var events: [InboxEvent] = []
    public private(set) var connected = false
    public private(set) var stopped = false
    public var errorMessage: String?
    public var onUpdate: (() -> Void)?
    public var onInteraction: ((Bool) -> Void)?
    public var onPeek: ((String) -> Bool)?
    private var peekBudget = PeekBudget()
    private var generation = -1
    private var watchTask: Task<Void, Never>?
    private let client: any AgentTransport
    private let defaults: UserDefaults
    public let catalogRoot: URL?
    public init(catalogRoot: URL? = nil, client: any AgentTransport = AgentClient(), defaults: UserDefaults = .standard) {
        self.client = client; self.defaults = defaults
        self.catalogRoot = catalogRoot ?? Bundle.main.resourceURL?.appendingPathComponent("Apps")
        do {
            if let root = self.catalogRoot, FileManager.default.fileExists(atPath: root.appendingPathComponent("catalog.json").path) {
                let value = try StrictJSON.decode(Data(contentsOf: root.appendingPathComponent("catalog.json")))
                catalog = try WireCoding.decoder().decode([AppCatalogEntry].self, from: WireCoding.encoder().encode(value))
                for entry in catalog { try Validation.relativePath(entry.folder) }
            }
        } catch { errorMessage = "App catalog unavailable: \(error.localizedDescription)" }
    }
    public var enabledInstances: [PluginInstance] { instances.filter(\.enabled) }
    public func manifest(for entry: AppCatalogEntry) -> PluginManifestV2? {
        guard let root = catalogRoot else { return nil }
        return try? PluginManifestV2.validated(Data(contentsOf: root.appendingPathComponent(entry.folder).appendingPathComponent("ledge-plugin.json")))
    }
    public func schema(for app: PluginInstallation) -> JSONValue {
        guard let name = app.manifest.configSchema else { return .object(["type": .string("object"), "properties": .empty]) }
        return (try? StrictJSON.decode(Data(contentsOf: app.directory.appendingPathComponent(name)))) ?? .empty
    }
    public func refresh() async {
        do { try accept(await client.call("apps.snapshot")); errorMessage = nil; if !instances.isEmpty { startWatch() } }
        catch { connected = false; errorMessage = error.localizedDescription }
    }
    private func accept(_ json: JSONValue) throws {
        installations = try WireCoding.decoder().decode([PluginInstallation].self, from: WireCoding.encoder().encode(json["installations"]))
        instances = try WireCoding.decoder().decode([PluginInstance].self, from: WireCoding.encoder().encode(json["instances"]))
        views = try WireCoding.decoder().decode([String: PluginViewSnapshot].self, from: WireCoding.encoder().encode(json["views"]))
        errors = json["errors"].object?.compactMapValues(\.string) ?? [:]
        running = Set(json["running"].array?.compactMap(\.string) ?? [])
        generation = Int(exactly: json["generation"].number ?? 0) ?? 0
        stopped = json["stopped"].bool ?? false; connected = true; onUpdate?()
        events = try WireCoding.decoder().decode([InboxEvent].self, from: WireCoding.encoder().encode(json["events"].array == nil ? JSONValue.array([]) : json["events"]))
        let pending = Set(json["pendingDelivery"].array?.compactMap(\.string) ?? [])
        let now = Date()
        let eligible = events.filter { item in
            guard pending.contains(item.id), now.timeIntervalSince(item.createdAt) < 900, let instance = instances.first(where: { $0.id == item.automationID && $0.enabled }) else { return false }
            return DeliveryPolicy().shouldPeek(event: item.event, preferences: instance.delivery, now: now, timezone: instance.schedule.timezone, presentationSafe: defaults.bool(forKey: "ledge.presentationSafe"), externalDisplay: NSScreen.screens.allSatisfy { $0.safeAreaInsets.top == 0 })
        }
        var budget = peekBudget
        if !stopped, !eligible.isEmpty, budget.consume(now: now), onPeek?(eligible.count == 1 ? "1 new app update" : "\(eligible.count) new app updates") == true {
            peekBudget = budget
            for event in eligible { Task { _ = try? await client.call("delivered", .object(["id": .string(event.id)])) } }
        }
    }
    private func startWatch() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            guard let self else { return }; defer { self.watchTask = nil }
            do {
                while !Task.isCancelled && !instances.isEmpty {
                    try accept(await client.call("apps.watch", .object(["generation": .number(Double(generation))])))
                }
            } catch { connected = false; errorMessage = error.localizedDescription }
        }
    }
    @discardableResult public func control(_ method: String, _ params: JSONValue = .empty) async -> Bool {
        do { _ = try await client.call(method, params); errorMessage = nil; await refresh(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    public func install(_ entry: AppCatalogEntry) async {
        guard let root = catalogRoot else { return }
        _ = await control("apps.install", .object(["path": .string(root.appendingPathComponent(entry.folder).path), "trust": .bool(true)]))
    }
    public func save(_ instance: PluginInstance) async -> Bool {
        do { return await control("apps.save", try WireCoding.value(instance)) }
        catch { errorMessage = error.localizedDescription; return false }
    }
    public func run(_ instance: PluginInstance, command: String? = nil, arguments: JSONValue = .empty, viewRevision: Int? = nil, confirmed: Bool = false) async {
        guard let app = installations.first(where: { $0.id == instance.installationID }) else { return }
        let selected = command ?? app.manifest.defaultCommand
        var approval = confirmed
        if app.manifest.commands.first(where: { $0.id == selected })?.destructive == true && !approval {
            onInteraction?(true)
            let alert = NSAlert(); alert.messageText = "Run this destructive app command?"; alert.informativeText = "\(app.manifest.name) · \(selected) may change data. Confirm only if you intend its effects."; alert.addButton(withTitle: "Run command"); alert.addButton(withTitle: "Cancel")
            approval = alert.runModal() == .alertFirstButtonReturn
            onInteraction?(false)
            guard approval else { return }
        }
        do { _ = await control("apps.run", try WireCoding.value(PluginActionRequest(instanceID: instance.id, command: selected, arguments: arguments, expectedRevision: instance.revision, viewRevision: viewRevision, confirmed: approval))) }
        catch { errorMessage = error.localizedDescription }
    }
    public func enableBackgroundService() async {
        do {
            _ = try AgentSecurity.requirement(identifiers: ["com.ledge.agent"])
            let service = SMAppService.agent(plistName: "com.ledge.agent.plist")
            try service.register()
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    public func openEventURL(instance: PluginInstance, eventID: String, actionID: String) async {
        do {
            let response = try await client.call("apps.eventURL", .object(["instanceID": .string(instance.id), "eventID": .string(eventID), "actionID": .string(actionID), "expectedRevision": .number(Double(instance.revision))]))
            guard let address = response.string, let url = URL(string: address), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw PlatformError.denied("Invalid app link") }
            guard NSWorkspace.shared.open(url) else { throw PlatformError.unavailable("No application could open this link") }
        } catch { errorMessage = error.localizedDescription }
    }
    public func stopForQuit() async -> Bool {
        watchTask?.cancel()
        if defaults.bool(forKey: "ledge.automation.keepRunning") { return true }
        do { _ = try await client.call("stop"); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
}
