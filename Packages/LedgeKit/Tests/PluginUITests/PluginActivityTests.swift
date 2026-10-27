import Foundation
import Testing
import AutomationDomain
import AgentIPC
@testable import PluginUI

@Test @MainActor func pluginActivityRejectsForeignAndStaleViewsAndLimitsFloods() throws {
    let store = PluginActivityStore()
    let first = PluginPresentation(instanceID: "one", root: .init(id: "body", kind: "text", text: "First"))
    #expect(try store.accept(first, instanceID: "one", now: 0, visible: true))
    #expect(throws: (any Error).self) { try store.accept(first, instanceID: "other", now: 1, visible: true) }
    #expect(!store.acceptingRevision(1, instanceID: "one"))
    for revision in 2...5 { var update = first; update.revision = revision; #expect(try store.accept(update, instanceID: "one", now: 0.1, visible: true)) }
    var flood = first; flood.revision = 6
    #expect(!(try store.accept(flood, instanceID: "one", now: 0.2, visible: true)))
    #expect(try store.accept(flood, instanceID: "one", now: 1.1, visible: true))
    store.remove(instanceID: "one")
    #expect(store.presentations.isEmpty)
}

private struct UnreachableAgent: AgentTransport {
    func call(_ method: String, _ params: JSONValue) async throws -> JSONValue { throw PlatformError.unavailable("Runner is unreachable") }
}
@Test @MainActor func quitDoesNotTreatDisconnectedAsSuccessfullyStopped() async {
    let store = AppLibraryStore(client: UnreachableAgent(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
    #expect(!store.connected)
    #expect(!(await store.stopForQuit()))
    #expect(store.errorMessage != nil)
}

private actor SnapshotAgent: AgentTransport {
    let snapshot: JSONValue
    init(_ snapshot: JSONValue) { self.snapshot = snapshot }
    func call(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        if method == "apps.watch" { try await Task.sleep(for: .seconds(20)) }
        return method == "stop" || method == "delivered" ? .bool(true) : snapshot
    }
}
@Test @MainActor func pendingAppEventsOfferOnePolicyControlledPeek() async throws {
    let instance = PluginInstance(installationID: "test.app", name: "Test", enabled: true)
    let event = InboxEvent(id: "event", automationID: instance.id, event: .init(sourceKey: "one", title: "Build completed", sensitivity: "public"), createdAt: .now)
    let snapshot: JSONValue = .object(["generation": .number(1), "installations": .array([]), "instances": try WireCoding.value([instance]), "events": try WireCoding.value([event]), "pendingDelivery": .array([.string("event")]), "views": .empty, "errors": .empty, "running": .array([]), "stopped": .bool(false)])
    let store = AppLibraryStore(client: SnapshotAgent(snapshot), defaults: UserDefaults(suiteName: UUID().uuidString)!)
    var offered = 0
    store.onPeek = { _ in offered += 1; return true }
    await store.refresh(); await store.refresh()
    #expect(offered == 1)
    _ = await store.stopForQuit()
}
