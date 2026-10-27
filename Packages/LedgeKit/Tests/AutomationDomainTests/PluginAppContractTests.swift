import Foundation
import Testing
@testable import AutomationDomain

private let manifestJSON = #"{"schemaVersion":2,"id":"dev.test.hello","version":"1.0.0","hostAPI":"2","name":"Hello","summary":"A fixture app","publisher":"Local developer","runtime":{"kind":"command","entry":"main.py","interpreter":"python3"},"capabilities":["events.publish","state.readwrite"],"commands":[{"id":"run","title":"Run"}],"defaultCommand":"run"}"#

@Test func pluginAppContractRejectsUnknownVersionAndUndeclaredCommands() throws {
    let manifest = try PluginManifestV2.validated(Data(manifestJSON.utf8))
    #expect(manifest.commands.first?.id == "run")
    #expect(throws: (any Error).self) { try PluginManifestV2.validated(Data(manifestJSON.replacingOccurrences(of: "\"schemaVersion\":2", with: "\"schemaVersion\":3").utf8)) }
    #expect(throws: (any Error).self) { try manifest.validateCommand("delete", arguments: .empty) }
}

@Test func pluginViewContractRejectsOversizeAndUnsafeNodes() throws {
    let node = PluginViewNode(id: "title", kind: "text", text: "Hello")
    try node.validate()
    #expect(throws: (any Error).self) { try PluginViewNode(id: "html", kind: "webview", text: "<script/>").validate() }
    #expect(throws: (any Error).self) { try PluginViewNode(id: "body", kind: "text", text: String(repeating: "x", count: 8193)).validate() }
    #expect(throws: (any Error).self) { try PluginViewNode(id: "list", kind: "list", children: (0..<201).map { .init(id: "n\($0)", kind: "text", text: "x") }).validate() }
}

@Test func destructiveDefaultCommandRequiresExplicitConfirmation() throws {
    let text = manifestJSON.replacingOccurrences(of: "\"title\":\"Run\"", with: "\"title\":\"Run\",\"destructive\":true")
    let manifest = try PluginManifestV2.validated(Data(text.utf8))
    #expect(throws: (any Error).self) { try manifest.validateInvocation("run", arguments: .empty, confirmed: false) }
    try manifest.validateInvocation("run", arguments: .empty, confirmed: true)
}
