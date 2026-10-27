import Foundation
import Testing
import AutomationDomain
@testable import AutomationStorage

private func appFixture() async throws -> (URL, SQLiteAutomationStore, PluginInstallation, PluginInstance) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try SQLiteAutomationStore(root: root, key: Data(repeating: 6, count: 32))
    let manifest = try PluginManifestV2.validated(Data(#"{"schemaVersion":2,"id":"dev.test.app","version":"1.0.0","hostAPI":"2","name":"App","summary":"Test","publisher":"Local","runtime":{"kind":"command","entry":"main.py","interpreter":"python3"},"capabilities":["state.readwrite","presentation.publish"],"commands":[{"id":"run","title":"Run"}],"defaultCommand":"run"}"#.utf8))
    let app = PluginInstallation(manifest: manifest, directory: root, executable: "/usr/bin/python3", arguments: [], digest: "fixture", source: "fixture", grants: manifest.capabilities)
    try await store.installApp(app)
    var instance = try await store.saveInstance(.init(installationID: app.id, name: "Test"))
    instance.enabled = true; instance = try await store.saveInstance(instance)
    return (root, store, app, instance)
}

@Test func retainedAppDataIncludesItsLastSuccessfulView() async throws {
    let (root, store, app, instance) = try await appFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let lease = try await store.acquireAppLease(instanceID: instance.id)
    let snapshot = PluginViewSnapshot(presentation: .init(instanceID: instance.id, root: .init(id: "body", kind: "text", text: "Retain me")))
    _ = try await store.commitCheckpoint(lease: lease, batch: .init(sequence: 1, expectedStateRevision: 0, result: .init(viewSnapshot: snapshot)))
    try await store.removeApp(app.id, keepData: true)
    #expect(try await store.appView(instanceID: instance.id)?.presentation.root.text == "Retain me")
    #expect(try await store.appInstances().isEmpty)
}

@Test func appCannotReuseLegacyOrArchivedInstanceIdentity() async throws {
    let (root, store, app, instance) = try await appFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try await store.apply([.init(id: "legacy", plugin: "dev.legacy@1.0.0")])
    await #expect(throws: (any Error).self) { try await store.apply([.init(id: instance.id, plugin: "dev.legacy@1.0.0")]) }
    await #expect(throws: (any Error).self) { try await store.saveInstance(.init(id: "legacy", installationID: app.id, name: "Collision")) }
    try await store.removeApp(app.id, keepData: true)
    try await store.installApp(app)
    await #expect(throws: (any Error).self) { try await store.saveInstance(.init(id: instance.id, installationID: app.id, name: "Implicit restore")) }
}

@Test func legacySchedulesPauseOnceWithoutLosingStateOrEventIdentity() async throws {
    let (root, store, _, _) = try await appFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let job = AutomationDefinition(id: "old-job", plugin: "dev.old@1.0.0", enabled: true)
    try await store.apply([job])
    let run = try await store.claim(jobID: job.id, occurrence: "one", now: .now)!
    try await store.complete(run, result: .init(events: [.init(sourceKey: "existing", title: "Keep event")], state: .object(["cursor": .number(1)])))
    let id = try await store.inbox().first!.id
    try await store.pauseLegacySchedulesForMigration()
    #expect(try await store.jobs().first?.enabled == false)
    #expect(try await store.state(jobID: job.id) == .object(["cursor": .number(1)]))
    #expect(try await store.inbox().first?.id == id)
    try await store.apply([job])
    try await store.pauseLegacySchedulesForMigration()
    #expect(try await store.jobs().first?.enabled == true)
}

@Test func successfulSnapshotCannotBeReplacedAtAnOlderOrEqualRevision() async throws {
    let (root, store, _, instance) = try await appFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let lease = try await store.acquireAppLease(instanceID: instance.id)
    let view = PluginViewSnapshot(presentation: .init(instanceID: instance.id, root: .init(id: "body", kind: "text", text: "First"), revision: 3))
    _ = try await store.commitCheckpoint(lease: lease, batch: .init(sequence: 1, expectedStateRevision: 0, result: .init(viewSnapshot: view)))
    await #expect(throws: (any Error).self) { try await store.commitCheckpoint(lease: lease, batch: .init(sequence: 2, expectedStateRevision: 1, result: .init(viewSnapshot: view))) }
}

@Test func pluginInstancesHaveIndependentStateAndRevocableCommits() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SQLiteAutomationStore(root: root, key: Data(repeating: 8, count: 32))
    let manifest = try PluginManifestV2.validated(Data(#"{"schemaVersion":2,"id":"dev.test.app","version":"1.0.0","hostAPI":"2","name":"App","summary":"Test","publisher":"Local","runtime":{"kind":"command","entry":"main.py","interpreter":"python3"},"capabilities":["state.readwrite","events.publish","presentation.publish"],"commands":[{"id":"run","title":"Run"}],"defaultCommand":"run"}"#.utf8))
    let installation = PluginInstallation(manifest: manifest, directory: root, executable: "/usr/bin/python3", arguments: [], digest: "fixture", source: "fixture", grants: manifest.capabilities)
    try await store.installApp(installation)
    var one = PluginInstance(installationID: installation.id, name: "One")
    let two = PluginInstance(installationID: installation.id, name: "Two")
    try await store.saveInstance(one); try await store.saveInstance(two)
    #expect(try await store.appInstances().allSatisfy { !$0.enabled })
    one.enabled = true; one = try await store.saveInstance(one)
    await #expect(throws: (any Error).self) { try await store.acquireAppLease(instanceID: one.id, expectedRevision: 1) }
    let lease = try await store.acquireAppLease(instanceID: one.id)
    let presentation = PluginPresentation(instanceID: one.id, root: .init(id: "hello", kind: "text", text: "Saved view"))
    let batch = ServiceCheckpoint(id: "checkpoint", sequence: 1, expectedStateRevision: 0, result: .init(state: .object(["cursor": .number(1)]), viewSnapshot: .init(presentation: presentation)))
    let receipt = try await store.commitCheckpoint(lease: lease, batch: batch)
    #expect(try await store.commitCheckpoint(lease: lease, batch: batch) == receipt)
    #expect(try await store.state(jobID: two.id) == .empty)
    #expect(try await store.appView(instanceID: one.id)?.presentation.root.text == "Saved view")
    one.enabled = false; try await store.saveInstance(one)
    await #expect(throws: (any Error).self) { try await store.commitCheckpoint(lease: lease, batch: .init(sequence: 2, expectedStateRevision: 1, result: .init(state: .empty))) }
    let reopened = try SQLiteAutomationStore(root: root, key: Data(repeating: 8, count: 32))
    #expect(try await reopened.appInstances().count == 2)
    #expect(try await reopened.state(jobID: one.id) == .object(["cursor": .number(1)]))
}
