import Foundation
import AppKit
import ServiceManagement
import AutomationDomain
import AutomationRuntime
import AutomationHost
import PluginRuntime
import AgentIPC

enum LedgeCLI {
    static let help = """
    Ledge — local programs, useful notch notifications

      ledge validate PLUGIN_DIR | CONFIG.json
      ledge init DIRECTORY [--language python|typescript]
      ledge dev PLUGIN_DIR [--fixture INPUT.json] [--interpreter /absolute/path]
      ledge plugin install PLUGIN_DIR --trust-local-code [--interpreter PATH]
      ledge plugins
      ledge automation apply CONFIG.json
      ledge connect github --name ACCOUNT --token-stdin
      ledge disconnect github --name ACCOUNT
      ledge run JOB_ID [--dry-run]
      ledge runs | ledge events | ledge status
      ledge stop | ledge resume
      ledge service enable | ledge service disable
      ledge ui open

    Plugins are trusted local programs with your user permissions.
    Dry runs suppress host commits/notifications, not independent native effects.
    """
    static func run(_ arguments: [String]) async throws -> JSONValue? {
        guard let command = arguments.first else { print(help); return nil }
        func argument(_ index: Int) throws -> String { guard arguments.indices.contains(index) else { throw PlatformError.invalid(help) }; return arguments[index] }
        func option(_ name: String) -> String? { guard let i = arguments.firstIndex(of: name), arguments.indices.contains(i + 1) else { return nil }; return arguments[i + 1] }
        func url(_ path: String) -> URL { URL(fileURLWithPath: path).standardizedFileURL }
        let client = AgentClient()
        switch command {
        case "--help", "help", "-h": print(help); return nil
        case "validate":
            let path = url(try argument(1)); var directory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: path.path, isDirectory: &directory)
            if directory.boolValue { let manifest = try ManifestValidator.validate(data: Data(contentsOf: path.appendingPathComponent("ledge-plugin.json"))); return .object(["valid": .bool(true), "plugin": .string(manifest.id)]) }
            let jobs = try ConfigurationValidator.validate(data: Data(contentsOf: path))
            for job in jobs { try ScheduleEvaluator.validate(job.schedule) }
            return .object(["valid": .bool(true), "automations": .number(Double(jobs.count))])
        case "plugin":
            guard try argument(1) == "install" else { throw PlatformError.invalid(help) }
            return try await client.call("install", .object(["path": .string(url(try argument(2)).path), "trust": .bool(arguments.contains("--trust-local-code")), "interpreter": option("--interpreter").map(JSONValue.string) ?? .null]))
        case "plugins": return try await client.call("plugins")
        case "automation":
            guard try argument(1) == "apply" else { throw PlatformError.invalid(help) }
            let data = try Data(contentsOf: url(try argument(2))); _ = try ConfigurationValidator.validate(data: data)
            return try await client.call("apply", StrictJSON.decode(data))
        case "run": return try await client.call("run", .object(["id": .string(try argument(1)), "dryRun": .bool(arguments.contains("--dry-run"))]))
        case "runs": return try await client.call("snapshot")["runs"]
        case "events": return try await client.call("snapshot")["events"]
        case "status": return try await client.call("status")
        case "stop", "resume": return try await client.call(command)
        case "connect":
            guard try argument(1) == "github", arguments.contains("--token-stdin"), let name = option("--name") else { throw PlatformError.invalid("Use: ledge connect github --name ACCOUNT --token-stdin") }
            guard let token = readLine(), !token.isEmpty else { throw PlatformError.invalid("Expected token on stdin") }
            return try await client.call("connect.github", .object(["name": .string(name), "token": .string(token.trimmingCharacters(in: .whitespacesAndNewlines))]))
        case "disconnect":
            guard try argument(1) == "github", let name = option("--name") else { throw PlatformError.invalid(help) }
            return try await client.call("disconnect.github", .object(["name": .string(name)]))
        case "service":
            let service = SMAppService.agent(plistName: "com.ledge.agent.plist")
            if try argument(1) == "enable" { try service.register() } else if try argument(1) == "disable" { try await service.unregister() } else { throw PlatformError.invalid(help) }
            return .object(["serviceStatus": .number(Double(service.status.rawValue))])
        case "ui":
            guard try argument(1) == "open" else { throw PlatformError.invalid(help) }
            await MainActor.run { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Ledge.app"), configuration: NSWorkspace.OpenConfiguration()) }
            return .object(["requested": .bool(true)])
        case "dev":
            let directory = url(try argument(1))
            let manifest = try ManifestValidator.validate(data: Data(contentsOf: directory.appendingPathComponent("ledge-plugin.json")))
            let executable = option("--interpreter") ?? ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/", "/bin/"].map { $0 + (manifest.runtime.interpreter ?? "python3") }.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? ""
            let fixture: JSONValue = try option("--fixture").map { try StrictJSON.decode(Data(contentsOf: url($0))) } ?? .empty
            let result = try await ProgramRunner().execute(executable: executable, arguments: [directory.appendingPathComponent(manifest.runtime.entry).path], directory: directory, request: .object(["runID": .string("preview"), "automationID": .string("preview"), "config": fixture["config"].object == nil ? .empty : fixture["config"], "state": fixture["state"].object == nil ? .empty : fixture["state"], "mode": .string("preview"), "now": .string(ISO8601DateFormatter().string(from: .now)), "hostProtocol": .string("1"), "command": .string(manifest.defaultCommand)]), timeout: 30) { method, params in
                if method == "host.state.get" { return fixture["state"].object == nil ? .empty : fixture["state"] }
                if method == "host.records.query" { return fixture["records"].array == nil ? .array([]) : fixture["records"] }
                let key = (params["operation"].string ?? "") + ":" + (params["params"]["repository"].string ?? "")
                guard let response = fixture["responses"].object?[key] else { throw PlatformError.unavailable("No fixture response for \(key); dev does not access live integrations") }
                return response
            }
            return try WireCoding.value(result)
        case "init":
            let directory = url(try argument(1))
            guard !FileManager.default.fileExists(atPath: directory.path) else { throw PlatformError.invalid("Directory already exists") }
            guard option("--language") == nil || option("--language") == "python" else { throw PlatformError.invalid("Python template is available; TypeScript SDK can be used with a compiled JS entry") }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let manifest = #"{"schemaVersion":1,"id":"dev.local.hello","version":"0.1.0","hostProtocol":"1","name":"Hello Ledge","runtime":{"kind":"local.command","entry":"main.py","interpreter":"python3"},"capabilities":["events.publish"],"commands":["scan"],"defaultCommand":"scan"}"#
            try Data(manifest.utf8).write(to: directory.appendingPathComponent("ledge-plugin.json"))
            let program = "import json,sys\nrequest=json.loads(sys.stdin.readline())\nprint(json.dumps({'jsonrpc':'2.0','id':request['id'],'result':{'events':[{'sourceKey':'hello','title':'Hello from your plugin','body':'Edit main.py to make this useful.'}]}}),flush=True)\n"
            try Data(program.utf8).write(to: directory.appendingPathComponent("main.py"))
            return .object(["created": .string(directory.path), "next": .string("ledge dev \(directory.path)")])
        default: throw PlatformError.invalid(help)
        }
    }
}

do {
    if let result = try await LedgeCLI.run(Array(CommandLine.arguments.dropFirst())) { print(String(decoding: try WireCoding.encoder().encode(result), as: UTF8.self)) }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    if let e = error as? PlatformError {
        switch e { case .invalid: exit(2); case .denied: exit(3); case .timeout: exit(5); case .unavailable: exit(6); case .cancelled: exit(4) }
    }
    exit(4)
}
