import SwiftUI
import AutomationDomain

public struct PluginNotchView: View {
    let store: AppLibraryStore
    let openLibrary: () -> Void
    let dismiss: () -> Void
    @State private var selection: String?
    @State private var confirmation: (PluginInstance, String, JSONValue, Int)?
    public init(store: AppLibraryStore, openLibrary: @escaping () -> Void, dismiss: @escaping () -> Void) { self.store = store; self.openLibrary = openLibrary; self.dismiss = dismiss }
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.stack.3d.up").foregroundStyle(.cyan)
                Text("Ledge").font(.headline)
                Spacer()
                Button(action: openLibrary) { Image(systemName: "square.grid.2x2") }.help("Apps Library").accessibilityLabel("Apps Library")
                Button(action: dismiss) { Image(systemName: "xmark") }.help("Close").accessibilityLabel("Close notch")
            }.buttonStyle(.plain)
            if store.enabledInstances.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "plus.app").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
                    Text("Your notch. Your apps.").font(.title3.weight(.semibold))
                    Text("Add only what belongs in your workflow.").font(.callout).foregroundStyle(.secondary)
                    Button("Install Apps", action: openLibrary).buttonStyle(.borderedProminent).tint(.cyan).accessibilityIdentifier("notch.install-apps")
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(store.enabledInstances.sorted { $0.pinned && !$1.pinned }) { instance in Button(instance.name) { selection = instance.id }.buttonStyle(.bordered).tint(selection == instance.id ? .cyan : .gray) } }
                }
                Divider().overlay(.white.opacity(0.12))
                if let instance = store.enabledInstances.first(where: { $0.id == selection }) ?? store.enabledInstances.first {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(store.events.filter { $0.automationID == instance.id && $0.unread }.prefix(3))) { item in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(item.event.title).font(.callout.weight(.semibold))
                                    Text(item.event.body).font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        ForEach(item.event.actions) { action in
                                            Button(action.label) { Task {
                                                if let command = action.command { await store.run(instance, command: command, arguments: action.arguments ?? .empty) }
                                                else { await store.openEventURL(instance: instance, eventID: item.id, actionID: action.id) }
                                            } }.buttonStyle(.bordered)
                                        }
                                        Spacer()
                                        Button("Mark read") { Task { _ = await store.control("ack", .object(["id": .string(item.id)])) } }.buttonStyle(.plain)
                                    }.font(.caption)
                                }.padding(10).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                            }
                            if let snapshot = store.views[instance.id] {
                                PluginViewRenderer(presentation: snapshot.presentation) { command, arguments in
                                    let destructive = store.installations.first(where: { $0.id == instance.installationID })?.manifest.commands.first(where: { $0.id == command })?.destructive == true
                                    if destructive { confirmation = (instance, command, arguments, snapshot.presentation.revision) }
                                    else { Task { await store.run(instance, command: command, arguments: arguments, viewRevision: snapshot.presentation.revision) } }
                                }
                                Text("Checked \(snapshot.checkedAt.formatted(date: .omitted, time: .shortened))\(snapshot.staleAfter.map { $0 < Date() ? " · stale" : "" } ?? "")").font(.caption2).foregroundStyle(.secondary)
                            } else { Text("No result yet. Run this app when you are ready.").foregroundStyle(.secondary) }
                            if let error = store.errors[instance.id] { Text(error).font(.caption).foregroundStyle(.orange) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack { Text(instance.name).font(.caption).foregroundStyle(.secondary); Spacer(); Button(store.running.contains(instance.id) ? "Running…" : "Run") { Task { await store.run(instance) } }.buttonStyle(.bordered).disabled(store.running.contains(instance.id)) }
                }
            }
            HStack { Text("Local-first · optional apps"); Spacer(); Text("⌘⌥Space") }.font(.caption2).foregroundStyle(.secondary)
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.white)
            .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26)).environment(\.colorScheme, .dark)
            .accessibilityIdentifier("notch.root")
            .confirmationDialog("Run this app action?", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
                if let request = confirmation { Button("Confirm action", role: .destructive) { confirmation = nil; Task { await store.run(request.0, command: request.1, arguments: request.2, viewRevision: request.3, confirmed: true) } } }
                Button("Cancel", role: .cancel) { confirmation = nil }
            }
    }
}
