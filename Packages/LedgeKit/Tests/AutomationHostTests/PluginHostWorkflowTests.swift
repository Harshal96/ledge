import Foundation
import Testing
import AutomationDomain
import AutomationStorage
import PluginRuntime
@testable import AutomationHost

@Test func optionalAppInstallsDisabledAndRunsIntoPersistentNativeView() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data(#"{"schemaVersion":2,"id":"dev.test.hello","version":"1.0.0","hostAPI":"2","name":"Hello","summary":"Fixture","publisher":"Local","runtime":{"kind":"command","entry":"main.py","interpreter":"/usr/bin/python3"},"capabilities":["state.readwrite","presentation.publish","events.publish"],"commands":[{"id":"run","title":"Run","argumentSchema":{"type":"object","properties":{"message":{"type":"string"}},"additionalProperties":false}}],"defaultCommand":"run"}"#.utf8).write(to: source.appendingPathComponent("ledge-plugin.json"))
    let program = "import sys,json\nr=json.loads(sys.stdin.readline()); p=r['params']\nprint(json.dumps({'jsonrpc':'2.0','id':r['id'],'result':{'state':{'ran':True},'viewSnapshot':{'presentation':{'protocolVersion':2,'instanceID':p['automationID'],'viewID':'main','revision':1,'sensitivity':'public','root':{'id':'title','kind':'text','text':p['arguments']['message']}},'checkedAt':p['now']}}}),flush=True)\n"
    try Data(program.utf8).write(to: source.appendingPathComponent("main.py"))
    let store = try SQLiteAutomationStore(root: root.appendingPathComponent("db"), key: Data(repeating: 9, count: 32))
    let registry = try PluginRegistry(root: root.appendingPathComponent("packages"))
    let host = PluginHost(store: store, registry: registry)
    let installation = try await registry.installApp(directory: source, trustLocalCode: true)
    try await store.installApp(installation)
    var instance = PluginInstance(installationID: installation.id, name: "Test")
    instance = try await store.saveInstance(instance)
    await #expect(throws: (any Error).self) { try await host.invoke(.init(instanceID: instance.id, command: "run", arguments: .object(["message": .string("Hello")]), expectedRevision: instance.revision)) }
    instance.enabled = true; instance = try await store.saveInstance(instance)
    _ = try await host.invoke(.init(instanceID: instance.id, command: "run", arguments: .object(["message": .string("Hello")]), expectedRevision: instance.revision))
    for _ in 0..<300 {
        if try await store.appView(instanceID: instance.id) != nil { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(try await store.appView(instanceID: instance.id)?.presentation.root.text == "Hello")
    #expect(try await store.state(jobID: instance.id) == .object(["ran": .bool(true)]))
    let lease = try await store.acquireAppLease(instanceID: instance.id)
    _ = try await store.commitCheckpoint(lease: lease, batch: .init(id: "event-fixture", sequence: 1, expectedStateRevision: 1, result: .init(events: [.init(sourceKey: "link", title: "Build completed", actions: [.init(id: "open", label: "View build", url: "https://github.com/o/r/actions/runs/1")])])) )
    try await store.releaseAppLease(lease)
    let event = try #require(await store.inbox().first)
    let request: JSONValue = .object(["instanceID": .string(instance.id), "eventID": .string(event.id), "actionID": .string("open"), "expectedRevision": .number(Double(instance.revision))])
    #expect(try await host.handle("apps.eventURL", params: request).string == "https://github.com/o/r/actions/runs/1")
    var stale = request.object!; stale["expectedRevision"] = .number(0)
    await #expect(throws: (any Error).self) { try await host.handle("apps.eventURL", params: .object(stale)) }
    try Data("package changed".utf8).write(to: installation.directory.appendingPathComponent("main.py"))
    instance.enabled = false
    _ = try await host.handle("apps.save", params: WireCoding.value(instance))
    #expect(try await store.appInstances().first?.enabled == false)
    await #expect(throws: (any Error).self) { try await host.handle("apps.eventURL", params: request) }
    await host.stop()
}
