import Foundation
import LedgeDomain
import AutomationDomain
import AgentIPC
import NotificationRouting
import Observation
import AppKit
import ServiceManagement
import SwiftUI

@MainActor @Observable
final class AutomationAppStore {
    static let shared = AutomationAppStore()
    var jobs: [AutomationDefinition] = []
    var events: [InboxEvent] = []
    var runs: [RunRecord] = []
    var connected = false
    var stopped = false
    var errorMessage: String?
    var onPeek: ((String) -> Void)?
    private var task: Task<Void, Never>?
    private var generation = -1
    private var budget = PeekBudget()
    private let client = AgentClient()

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                var snapshot = try await client.call("snapshot")
                while !Task.isCancelled {
                    try accept(snapshot)
                    snapshot = try await client.call("watch", .object(["generation": .number(Double(generation))]))
                }
            } catch { connected = false; errorMessage = error.localizedDescription }
        }
    }
    func refresh() async { do { try accept(await client.call("snapshot")) } catch { errorMessage = error.localizedDescription; connected = false } }
    func control(_ method: String, _ params: JSONValue = .empty) async {
        do { _ = try await client.call(method, params); errorMessage = nil; await refresh(); start() }
        catch { errorMessage = error.localizedDescription }
    }
    func enableService(_ enable: Bool) async {
        do {
            let service = SMAppService.agent(plistName: "com.ledge.agent.plist")
            if enable { try service.register(); if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() } }
            else { _ = try? await client.call("stop"); try await service.unregister() }
            await refresh(); if enable { start() }
        } catch { errorMessage = error.localizedDescription }
    }
    func stopForQuit() async { if !UserDefaults.standard.bool(forKey: "ledge.automation.keepRunning") { _ = try? await client.call("stop") } }
    private func accept(_ snapshot: JSONValue) throws {
        let isFirst = generation < 0
        jobs = try WireCoding.decoder().decode([AutomationDefinition].self, from: WireCoding.encoder().encode(snapshot["jobs"]))
        events = try WireCoding.decoder().decode([InboxEvent].self, from: WireCoding.encoder().encode(snapshot["events"]))
        runs = try WireCoding.decoder().decode([RunRecord].self, from: WireCoding.encoder().encode(snapshot["runs"]))
        stopped = snapshot["stopped"].bool ?? false; generation = Int(exactly: snapshot["generation"].number ?? 0) ?? 0; connected = true; errorMessage = nil
        let pending = Set(snapshot["pendingDelivery"].array?.compactMap(\.string) ?? [])
        let safe = UserDefaults.standard.bool(forKey: "ledge.presentationSafe")
        let eligible = events.filter { item in
            guard pending.contains(item.id), let job = jobs.first(where: { $0.id == item.automationID }) else { return false }
            return DeliveryPolicy().shouldPeek(event: item.event, preferences: job.delivery, now: .now, timezone: job.schedule.timezone, presentationSafe: safe, externalDisplay: NSScreen.screens.allSatisfy { $0.safeAreaInsets.top == 0 })
        }
        if !isFirst && !eligible.isEmpty && budget.consume(now: .now) {
            onPeek?(eligible.count == 1 ? "1 new update" : "\(eligible.count) new updates")
            for event in eligible { Task { _ = try? await client.call("delivered", .object(["id": .string(event.id)])) } }
        }
    }
}

struct AutomationNotchView: View {
    let store: AutomationAppStore
    let capture: () -> Void
    let settings: () -> Void
    let dismiss: () -> Void
    @State private var selected: String?
    @State private var confirmURL: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "bolt.horizontal.circle.fill").foregroundStyle(.cyan)
                Text("Ledge").font(.headline)
                Text("\(store.events.filter(\.unread).count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button(action: capture) { Image(systemName: "square.and.pencil") }.help("Quick Capture")
                Button(action: settings) { Image(systemName: "gearshape") }.help("Settings").keyboardShortcut(",", modifiers: .command)
                Button(action: dismiss) { Image(systemName: "xmark") }.keyboardShortcut(.escape, modifiers: [])
            }.buttonStyle(.plain)
            HStack(spacing: 7) {
                Circle().fill(store.connected && !store.stopped ? .green : .orange).frame(width: 6, height: 6)
                Text(store.connected ? (store.stopped ? "Automations paused" : "\(store.jobs.filter(\.enabled).count) scheduled automations") : "Connect your background runner in Settings")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Divider().overlay(.white.opacity(0.12))
            if store.events.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "tray").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("Your next useful update belongs here").font(.headline)
                    Text("Connect a plugin, choose its schedule, and let Ledge bring the results to your notch.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Configure automations", action: settings).buttonStyle(.bordered)
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(store.events) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(item.event.title).font(.callout.weight(.semibold)); Spacer(); if item.unread { Circle().fill(.cyan).frame(width: 5, height: 5) } }
                                Text(item.event.body).font(.caption).foregroundStyle(.secondary).lineLimit(selected == item.id ? nil : 3)
                                HStack {
                                    ForEach(item.event.actions) { action in
                                        Button(action.label) {
                                            if let raw = action.url, let url = URL(string: raw), url.scheme == "https" { confirmURL = url }
                                            else if let command = action.command { Task { await store.control("run", .object(["id": .string(item.automationID), "command": .string(command), "arguments": action.arguments ?? .empty])) } }
                                        }.buttonStyle(.bordered)
                                    }
                                    Spacer()
                                    Button("Read") { Task { await store.control("ack", .object(["id": .string(item.id)])) } }.buttonStyle(.plain).foregroundStyle(.secondary)
                                }.controlSize(.small)
                            }
                            .padding(12).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                            .onTapGesture { selected = item.id }
                            .accessibilityIdentifier("automation.event.\(item.id)")
                        }
                    }
                }
            }
            HStack { Text("Runs on this Mac").font(.caption2).foregroundStyle(.secondary); Spacer(); Text("⌘⌥Space").font(.caption2.monospaced()).foregroundStyle(.secondary) }
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white).background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .environment(\.colorScheme, .dark)
        .confirmationDialog("Open this resource? Eligibility may have changed since it was checked.", isPresented: Binding(get: { confirmURL != nil }, set: { if !$0 { confirmURL = nil } })) {
            if let url = confirmURL { Button("Open on \(url.host ?? "web")") { NSWorkspace.shared.open(url); confirmURL = nil } }
        }
    }
}

struct AutomationSettingsView: View {
    @State private var store = AutomationAppStore.shared
    @State private var configText = "{\n  \"schemaVersion\": 1,\n  \"automations\": []\n}"
    @State private var account = "github-personal"
    @State private var token = ""
    @State private var trustPlugin = false
    @State private var status: String?
    @AppStorage("ledge.automation.keepRunning") private var keepRunning = false
    @AppStorage("ledge.recovery.menuIcon") private var recoveryIcon = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(store.connected ? "Runner connected" : "Runner not connected", systemImage: "bolt.circle")
                    Spacer()
                    Button("Enable background runner") { Task { await store.enableService(true) } }
                    Button("Disable") { Task { await store.enableService(false) } }
                }
                Text("Scheduled programs run with your user permissions. Enable only plugins whose code you trust.").font(.callout).foregroundStyle(.secondary)
                Toggle("Keep automations running when I quit the interface", isOn: $keepRunning)
                Toggle("Show optional recovery icon in the menu bar (after relaunch)", isOn: $recoveryIcon)
                HStack { Button("Stop all") { Task { await store.control("stop") } }; Button("Resume") { Task { await store.control("resume") } }; Button("Refresh") { Task { await store.refresh() } } }
                Divider()
                Text("Plugins").font(.headline)
                Toggle("I have reviewed the local plugin's code and trust it to run", isOn: $trustPlugin)
                Button("Install local plugin…") { choosePlugin() }.disabled(!trustPlugin)
                Divider()
                Text("GitHub connection").font(.headline)
                TextField("Connection name", text: $account)
                SecureField("Read-only GitHub token", text: $token)
                HStack {
                    Button("Connect") { let value = token; token = ""; Task { await store.control("connect.github", .object(["name": .string(account), "token": .string(value)])) } }.disabled(token.isEmpty)
                    Button("Disconnect") { Task { await store.control("disconnect.github", .object(["name": .string(account)])) } }
                }
                Divider()
                Text("Automations").font(.headline)
                ForEach(store.jobs) { job in
                    HStack {
                        VStack(alignment: .leading) { Text(job.id); Text(job.plugin).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Run now") { Task { await store.control("run", .object(["id": .string(job.id)])) } }
                    }
                }
                TextEditor(text: $configText).font(.system(.caption, design: .monospaced)).frame(minHeight: 180).accessibilityLabel("Automation JSON configuration")
                HStack {
                    Button("Load current configuration") { loadConfiguration() }
                    Button("Validate and apply") { applyConfiguration() }
                }
                if let status { Text(status).font(.caption) }
                if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                Divider()
                Text("Recent runs").font(.headline)
                ForEach(Array(store.runs.prefix(20))) { run in
                    VStack(alignment: .leading) { Text("\(run.automationID) · \(run.outcome)"); if let summary = run.summary { Text(summary).font(.caption).foregroundStyle(.secondary) } }
                }
            }.padding(20)
        }.onAppear { store.start() }
    }
    private func choosePlugin() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.control("install", .object(["path": .string(url.path), "trust": .bool(true)])) }
    }
    private func loadConfiguration() {
        let encoder = WireCoding.encoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(JSONValue.object(["schemaVersion": .number(1), "automations": (try? WireCoding.value(store.jobs)) ?? .array([])])) { configText = String(decoding: data, as: UTF8.self) }
    }
    private func applyConfiguration() {
        do { let data = Data(configText.utf8); _ = try ConfigurationValidator.validate(data: data); let value = try StrictJSON.decode(data); Task { await store.control("apply", value); status = store.errorMessage == nil ? "Configuration applied." : nil } }
        catch { status = error.localizedDescription }
    }
}

/// Composition inputs owned by the app target. Feature services remain behind
/// this boundary so a denied Calendar/Screen Recording request cannot prevent
/// the shell and its recovery surface from launching.
public struct AppEnvironment: Sendable {
    public typealias CandidateSnapshot = @Sendable () async -> [ActionCandidate]

    public let candidateSnapshot: CandidateSnapshot
    public let enabledFeatures: Set<FeatureID>
    public let presentationSafe: Bool

    public init(
        candidateSnapshot: @escaping CandidateSnapshot = { [] },
        enabledFeatures: Set<FeatureID> = Set(FeatureID.allCases),
        presentationSafe: Bool = false
    ) {
        self.candidateSnapshot = candidateSnapshot
        self.enabledFeatures = enabledFeatures
        self.presentationSafe = presentationSafe
    }

    public static let live = AppEnvironment()

    /// A deterministic failure fixture: no feature service is started, but
    /// the coordinator must still expose Settings and Quit recovery.
    public static let allServicesFailing = AppEnvironment(enabledFeatures: [])

    #if LEDGE_UITESTING
    static let uiTesting = UITestFixture(arguments: ProcessInfo.processInfo.arguments)
    #endif
}

#if LEDGE_UITESTING
struct UITestFixture: Sendable {
    let screen: String
    let hotKeyResult: String
    let action: String?
    let presentationSafe: Bool
    let audioCard: Bool

    init(arguments: [String]) {
        func value(for flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        screen = value(for: "-ledge-screen-fixture") ?? "notched"
        hotKeyResult = value(for: "-ledge-hotkey-result") ?? "registered"
        action = value(for: "-ledge-shell-action")
        presentationSafe = value(for: "-ledge-presentation-safe") == "YES"
        audioCard = value(for: "-ledge-ui-fixture") == "audio-card"
    }
}
#endif
