import Foundation
import Testing
@testable import AutomationDomain

@Test func rejectsUnsupportedPluginRuntimeAndVersion() throws {
    let manifest = #"{"schemaVersion":1,"id":"dev.test.check","version":"1.0.0","hostProtocol":"1","name":"Check","runtime":{"kind":"local.command","entry":"check.py","interpreter":"python3"},"capabilities":["events.publish"],"commands":["scan"],"defaultCommand":"scan"}"#
    let valid = try ManifestValidator.validate(data: Data(manifest.utf8))
    #expect(valid.id == "dev.test.check")
    #expect(throws: (any Error).self) { try ManifestValidator.validate(data: Data(manifest.replacingOccurrences(of: "local.command", with: "remote.shell").utf8)) }
    #expect(throws: (any Error).self) { try ManifestValidator.validate(data: Data(manifest.replacingOccurrences(of: "\"hostProtocol\":\"1\"", with: "\"hostProtocol\":\"2\"").utf8)) }
    #expect(throws: (any Error).self) { try ManifestValidator.validate(data: Data(manifest.replacingOccurrences(of: "check.py", with: "../escape.py").utf8)) }
}

@Test func duplicateKeysAndIDsFailWithoutNormalizing() throws {
    #expect(throws: (any Error).self) { try StrictJSON.decode(Data(#"{"id":"a","id":"b"}"#.utf8)) }
    #expect(throws: (any Error).self) { try StrictJSON.decode(Data(#"{"\u0069d":"a","id":"b"}"#.utf8)) }
    let job = #"{"id":"test","plugin":"dev.test.check@1.0.0","command":"scan","schedule":{"cron":"*/15 * * * *","timezone":"Asia/Kolkata"},"config":{},"delivery":{"mode":"digest","surface":"notch"}}"#
    #expect(throws: (any Error).self) { try ConfigurationValidator.validate(data: Data("{\"schemaVersion\":1,\"automations\":[\(job),\(job)]}".utf8)) }
}

@Test func configurationPreservesPluginBindingsAndValidatesSchedule() throws {
    let data = Data(#"{"schemaVersion":1,"automations":[{"id":"watch","plugin":"dev.test.check@1.0.0","command":"scan","connection":"github-personal","schedule":{"cron":"*/15 * * * *","timezone":"Asia/Kolkata"},"config":{"repositories":["owner/repo"]},"delivery":{"mode":"digest","surface":"notch"}}]}"#.utf8)
    let jobs = try ConfigurationValidator.validate(data: data)
    #expect(jobs[0].connection == "github-personal")
    #expect(jobs[0].schedule.timezone == "Asia/Kolkata")
    #expect(throws: (any Error).self) { try ConfigurationValidator.validate(data: Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "Asia/Kolkata", with: "invalid/zone").utf8)) }
}

@Test func eventCannotInjectShellOrForgeIdentity() throws {
    #expect(throws: (any Error).self) { try HostEvent.validated(data: Data(#"{"sourceKey":"one","title":"Check","pluginID":"other","actions":[]}"#.utf8)) }
    #expect(throws: (any Error).self) { try HostEvent.validated(data: Data(#"{"sourceKey":"one","title":"Check","actions":[{"id":"run","label":"Run","shell":"rm -rf ."}]}"#.utf8)) }
    let event = try HostEvent.validated(data: Data(#"{"sourceKey":"one","title":"Check","body":"Useful","actions":[{"id":"open","label":"Open","url":"https://github.com/owner/repo/issues/1"}]}"#.utf8))
    #expect(event.title == "Check")
}
