import Foundation
import Testing
import AutomationDomain
import AutomationStorage
import PluginRuntime
import IntegrationKit
@testable import AutomationHost

@Test func trustedLocalPluginCommitsOnceAndDryRunDoesNotPublish() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let manifest = #"{"schemaVersion":1,"id":"dev.test.workflow","version":"1.0.0","hostProtocol":"1","name":"Workflow fixture","runtime":{"kind":"local.command","entry":"main.sh","interpreter":"/bin/sh"},"capabilities":["events.publish","state.readwrite"],"commands":["scan"],"defaultCommand":"scan"}"#
    try Data(manifest.utf8).write(to: source.appendingPathComponent("ledge-plugin.json"))
    let program = #"printf '%s\n' '{"jsonrpc":"2.0","id":"run","result":{"events":[{"sourceKey":"fixture","title":"Local fixture"}],"state":{"cursor":1},"summary":"fixture complete"}}'"#
    try Data(program.utf8).write(to: source.appendingPathComponent("main.sh"))
    let store = try SQLiteAutomationStore(root: root.appendingPathComponent("database"), key: Data(repeating: 9, count: 32))
    let registry = try PluginRegistry(root: root.appendingPathComponent("plugins"))
    _ = try await registry.install(directory: source, trustLocalCode: true)
    let host = AutomationHost(store: store, registry: registry, credentials: CredentialStore())
    let job = AutomationDefinition(id: "fixture", plugin: "dev.test.workflow@1.0.0")
    try await store.apply([job])
    for dryRun in [true, false, false] {
        let before = try await store.history().count
        _ = try await host.handle("run", params: .object(["id": .string("fixture"), "dryRun": .bool(dryRun)]))
        var finished = false
        for _ in 0..<200 {
            let history = try await store.history()
            if history.count > before, history.first?.outcome != "running" { finished = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(finished)
        #expect(try await store.history().first?.outcome == (dryRun ? "preview" : "succeeded"))
        #expect(try await store.inbox().count == (dryRun ? 0 : 1))
    }
    #expect(try await store.state(jobID: "fixture") == .object(["cursor": .number(1)]))
    _ = try await host.handle("stop", params: .empty)
    await #expect(throws: (any Error).self) { try await host.handle("run", params: .object(["id": .string("fixture")])) }
    await #expect(throws: (any Error).self) { try await host.handle("watch", params: .object(["generation": .number(1e100)])) }
}
