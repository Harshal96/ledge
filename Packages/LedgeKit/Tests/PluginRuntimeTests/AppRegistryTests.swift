import Foundation
import Testing
import AutomationDomain
@testable import PluginRuntime

@Test func appInstallRequiresTrustAndPinsPackageContents() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data(#"{"schemaVersion":2,"id":"dev.test.app","version":"1.0.0","hostAPI":"2","name":"App","summary":"Test","publisher":"Local","runtime":{"kind":"command","entry":"main.py","interpreter":"/bin/sh"},"capabilities":[],"commands":[{"id":"run","title":"Run"}],"defaultCommand":"run"}"#.utf8).write(to: source.appendingPathComponent("ledge-plugin.json"))
    try Data("exit 0".utf8).write(to: source.appendingPathComponent("main.py"))
    let registry = try PluginRegistry(root: root.appendingPathComponent("installed"))
    await #expect(throws: (any Error).self) { try await registry.installApp(directory: source, trustLocalCode: false) }
    let app = try await registry.installApp(directory: source, trustLocalCode: true)
    try await registry.verifyApp(app)
    try Data("changed".utf8).write(to: app.directory.appendingPathComponent("main.py"))
    await #expect(throws: (any Error).self) { try await registry.verifyApp(app) }
}

@Test func packageDigestFramesFileNamesAndContentsUnambiguously() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data(#"{"schemaVersion":2,"id":"dev.test.app","version":"1.0.0","hostAPI":"2","name":"App","summary":"Test","publisher":"Local","runtime":{"kind":"command","entry":"main.py","interpreter":"/bin/sh"},"capabilities":[],"commands":[{"id":"run","title":"Run"}],"defaultCommand":"run"}"#.utf8).write(to: source.appendingPathComponent("ledge-plugin.json"))
    try Data("exit 0".utf8).write(to: source.appendingPathComponent("main.py"))
    try Data("x/bc".utf8).write(to: source.appendingPathComponent("a"))
    let registry = try PluginRegistry(root: root.appendingPathComponent("installed"))
    let app = try await registry.installApp(directory: source, trustLocalCode: true)
    try Data("x".utf8).write(to: app.directory.appendingPathComponent("a"))
    try Data("c".utf8).write(to: app.directory.appendingPathComponent("b"))
    await #expect(throws: (any Error).self) { try await registry.verifyApp(app) }
}
