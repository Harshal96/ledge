import SwiftUI
import AppKit
import AutomationDomain
import ShellFeature

public struct AppLibraryView: View {
    @State private var store = AppLibraryStore.shared
    @State private var section = "Discover"
    @State private var installing: AppCatalogEntry?
    @State private var configuring: PluginInstallation?
    @State private var editing: PluginInstance?
    @State private var removing: PluginInstallation?
    @State private var connectionName = "personal"
    @State private var token = ""
    @AppStorage("ledge.automation.keepRunning") private var keepRunning = false
    @AppStorage("ledge.shell.displayID") private var displayID = ""
    @AppStorage("ledge.presentationSafe") private var presentationSafe = false
    public init() {}
    public var body: some View {
        NavigationSplitView {
            List(["Discover", "Installed", "Connections", "Developer"], id: \.self, selection: $section) { name in
                Label(name, systemImage: symbol(name)).padding(.vertical, 5)
            }.navigationTitle("Ledge").navigationSplitViewColumnWidth(155)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) { Text(section == "Discover" ? "Make the notch yours." : section).font(.system(size: 27, weight: .semibold, design: .rounded)); Text(subtitle).foregroundStyle(.secondary) }
                        Spacer()
                        Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh runner status")
                    }
                    if let error = store.errorMessage {
                        VStack(alignment: .leading, spacing: 7) { Label("Runner needs attention", systemImage: "exclamationmark.circle").font(.callout.weight(.semibold)); Text(error).font(.caption).textSelection(.enabled); Text("Browsing the app library does not need a runner or account.").font(.caption).foregroundStyle(.secondary) }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    switch section {
                    case "Installed": installed
                    case "Connections": connections
                    case "Developer": developer
                    default: discover
                    }
                }.padding(26)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 540)
        .task { await store.refresh() }
        .confirmationDialog("Install \(installing?.name ?? "app")?", isPresented: Binding(get: { installing != nil }, set: { if !$0 { installing = nil } })) {
            if let entry = installing { Button("Trust local code and install") { installing = nil; Task { await store.install(entry); section = "Installed" } } }
            Button("Cancel", role: .cancel) { installing = nil }
        } message: {
            Text("This program runs with your user permissions. Requested host capabilities: \(installing.flatMap { store.manifest(for: $0) }?.capabilities.joined(separator: ", ") ?? "inspect manifest"). Installation does not enable it, connect an account, or start a schedule.")
        }
        .confirmationDialog("Uninstall \(removing?.manifest.name ?? "app")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            if let app = removing {
                Button("Uninstall and retain encrypted data") { removing = nil; Task { _ = await store.control("apps.remove", .object(["id": .string(app.id), "keepData": .bool(true)])) } }
                Button("Uninstall and delete app data", role: .destructive) { removing = nil; Task { _ = await store.control("apps.remove", .object(["id": .string(app.id), "keepData": .bool(false)])) } }
            }
        } message: { Text("All of this app's instances and scheduled work will be disabled. Other apps and shared connections are retained.") }
        .sheet(item: $configuring) { app in PluginSetupView(app: app, instance: editing, store: store) }
    }
    private var subtitle: String {
        switch section { case "Installed": "Only the apps you choose. Configure first, enable when ready."; case "Connections": "Credentials stay in Keychain. Apps receive scoped references."; case "Developer": "Local code. Native views. Your workflow."; default: "Choose optional apps. Nothing runs until you enable it." }
    }
    private func symbol(_ name: String) -> String { switch name { case "Installed": "square.stack.3d.up"; case "Connections": "link"; case "Developer": "chevron.left.forwardslash.chevron.right"; default: "square.grid.2x2" } }
    private var discover: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ForEach(store.catalog) { entry in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Image(systemName: entry.icon).font(.system(size: 22)).foregroundStyle(.cyan).frame(width: 46, height: 46).background(.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 13)); Spacer(); Text(entry.category).font(.caption).foregroundStyle(.secondary) }
                        Text(entry.name).font(.headline)
                        Text(entry.summary).font(.callout).foregroundStyle(.secondary).frame(minHeight: 60, alignment: .top)
                        Spacer(minLength: 0)
                        HStack { Text("Optional · local-first").font(.caption2).foregroundStyle(.secondary); Spacer(); Button(store.installations.contains(where: { $0.id == entry.id }) ? "Installed" : "Install") { installing = entry }.disabled(store.installations.contains(where: { $0.id == entry.id })) }
                    }.padding(18).frame(minHeight: 220).background(.background, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
                }
            }
            if store.catalog.isEmpty { ContentUnavailableView("No catalog available", systemImage: "shippingbox", description: Text("You can still install a reviewed local plugin folder.")) }
            Button("Install a local app…") { chooseLocalApp() }.buttonStyle(.bordered)
            Text("Bundled does not mean installed. Installing does not mean enabled.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var installed: some View {
        VStack(alignment: .leading, spacing: 20) {
            if store.installations.isEmpty { ContentUnavailableView("No apps installed", systemImage: "square.stack.3d.up", description: Text("Start with one app from Discover, or create your own.")); Button("Browse apps") { section = "Discover" } }
            ForEach(store.installations) { app in
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { VStack(alignment: .leading) { Text(app.manifest.name).font(.headline); Text("\(app.manifest.version) · \(app.publisherStatus)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Add instance") { editing = nil; configuring = app }; Button { removing = app } label: { Image(systemName: "trash") }.help("Uninstall app") }
                        ForEach(store.instances.filter { $0.installationID == app.id }) { instance in
                            HStack {
                                Toggle(instance.name, isOn: Binding(get: { instance.enabled }, set: { value in var changed = instance; changed.enabled = value; Task { _ = await store.save(changed) } }))
                                Spacer()
                                Button("Configure") { editing = instance; configuring = app }
                                Button(store.running.contains(instance.id) ? "Running…" : "Run") { Task { await store.run(instance) } }.disabled(!instance.enabled || store.running.contains(instance.id))
                            }
                            if let error = store.errors[instance.id] { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                        }
                        if !store.instances.contains(where: { $0.installationID == app.id }) { Text("Installed, not configured or running.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(8)
                }
            }
        }
    }
    private var connections: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.installations.contains(where: { ($0.manifest.providerDependencies ?? []).contains("github") }) {
                ContentUnavailableView("No connections needed", systemImage: "link", description: Text("Install an app that declares a connection provider to configure it here."))
            } else {
                Text("GitHub · read-only provider").font(.headline)
                TextField("Connection name", text: $connectionName)
                SecureField("Read-only token", text: $token)
                HStack {
                    Button("Connect") { let secret = token; token = ""; Task { _ = await store.control("connect.github", .object(["name": .string(connectionName), "token": .string(secret)])) } }.disabled(token.isEmpty)
                    Button("Disconnect") { Task { _ = await store.control("disconnect.github", .object(["name": .string(connectionName)])) } }
                }
                Text("Use this connection name in your app instance. No token is exported in configuration.").font(.caption).foregroundStyle(.secondary)
            }
        }.textFieldStyle(.roundedBorder)
    }
    private var developer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A program, a manifest, a native app.").font(.headline)
            Text("Create a plugin with the CLI, preview it against fixtures, then install the same package. No Swift changes or host rebuild required.")
            Text("ledge init ./my-app\nledge dev ./my-app --fixture ./input.json\nledge app install ./my-app --trust-local-code").font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            Button("Enable signed background runner") { Task { await store.enableBackgroundService() } }
            Toggle("Keep scheduled apps running when I quit the interface", isOn: $keepRunning)
            Picker("Notch display", selection: $displayID) {
                Text("Automatic — prefer camera housing").tag("")
                Text("Follow pointer on explicit open").tag("pointer")
                ForEach(NSScreen.screens, id: \.localizedName) { screen in
                    Text(screen.localizedName).tag(String((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0))
                }
            }
            Button("Reset notch position") { displayID = "" }
            Toggle("Presentation safe — suppress automatic peeks", isOn: $presentationSafe)
            if store.stopped { Label("All automation is stopped. Resume explicitly to run apps.", systemImage: "pause.circle").foregroundStyle(.orange) }
            HStack { Button("Stop all") { Task { _ = await store.control("stop") } }; Button("Resume") { Task { _ = await store.control("resume") } } }
            LabeledContent("Running build", value: "\(BuildIdentity.current.version) (\(BuildIdentity.current.build))")
            LabeledContent("Source revision", value: BuildIdentity.current.commit)
            Text(BuildIdentity.current.executableURL.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            Text("The production agent requires matching Apple signing identities. An unsigned preview does not weaken that requirement.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func chooseLocalApp() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
        guard picker.runModal() == .OK, let folder = picker.url else { return }
        let alert = NSAlert(); alert.messageText = "Trust this local app?"; alert.informativeText = "Review its code and manifest first. It will run with your macOS user permissions. Installation alone does not enable it.\n\(folder.path)"; alert.addButton(withTitle: "Trust and install"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { _ = await store.control("apps.install", .object(["path": .string(folder.path), "trust": .bool(true)])); section = "Installed" }
    }
}

struct PluginSetupView: View {
    let app: PluginInstallation
    let store: AppLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PluginInstance
    @State private var advanced = false
    @State private var configText = ""
    @State private var cron = ""
    @State private var error: String?
    init(app: PluginInstallation, instance: PluginInstance?, store: AppLibraryStore) {
        self.app = app; self.store = store
        let draft = instance ?? PluginInstance(installationID: app.id, name: app.manifest.name, config: app.manifest.defaultConfig ?? .empty)
        _draft = State(initialValue: draft); _cron = State(initialValue: draft.schedule.cron ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure \(app.manifest.name)").font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Instance name", text: $draft.name)
                    PluginFormRenderer(schema: store.schema(for: app), draft: $draft.config)
                    TextField("Connection name (optional)", text: Binding(get: { draft.connection ?? "" }, set: { draft.connection = $0.isEmpty ? nil : $0 }))
                    TextField("Cron — leave empty for manual runs", text: $cron).font(.system(.body, design: .monospaced))
                    TextField("Timezone", text: $draft.schedule.timezone)
                    Toggle("Pin this app in the notch", isOn: $draft.pinned)
                    DisclosureGroup("Advanced JSON", isExpanded: $advanced) { TextEditor(text: $configText).font(.system(.caption, design: .monospaced)).frame(height: 150); Button("Use JSON") { do { draft.config = try StrictJSON.decode(Data(configText.utf8)); error = nil } catch { self.error = error.localizedDescription } } }.onChange(of: advanced) { _, value in if value { let encoder = WireCoding.encoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; configText = String(decoding: (try? encoder.encode(draft.config)) ?? Data(), as: UTF8.self) } }
                }.textFieldStyle(.roundedBorder)
            }
            Text("Saving does not enable a new instance. Choose Enable in Installed when you are ready.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save configuration") { Task { draft.schedule.cron = cron.isEmpty ? nil : cron; if await store.save(draft) { dismiss() } else { error = store.errorMessage } } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 550, height: 620)
    }
}
