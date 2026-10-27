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
      ledge test PLUGIN_DIR --fixture INPUT.json
      ledge app install DIR --trust-local-code | list | configure INSTANCE.json
      ledge app disable INSTANCE_ID | uninstall APP_ID [--delete-data]
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
            if directory.boolValue {
                let data = try Data(contentsOf: path.appendingPathComponent("ledge-plugin.json"))
                let json = try StrictJSON.decode(data)
                let id = json["schemaVersion"].number == 2 ? try PluginManifestV2.validated(data).id : try ManifestValidator.validate(data: data).id
                return .object(["valid": .bool(true), "plugin": .string(id)])
            }
            let jobs = try ConfigurationValidator.validate(data: Data(contentsOf: path))
            for job in jobs { try ScheduleEvaluator.validate(job.schedule) }
            return .object(["valid": .bool(true), "automations": .number(Double(jobs.count))])
        case "plugin":
            guard try argument(1) == "install" else { throw PlatformError.invalid(help) }
            return try await client.call("install", .object(["path": .string(url(try argument(2)).path), "trust": .bool(arguments.contains("--trust-local-code")), "interpreter": option("--interpreter").map(JSONValue.string) ?? .null]))
        case "app":
            switch try argument(1) {
            case "list": return try await client.call("apps.snapshot")
            case "install": return try await client.call("apps.install", .object(["path": .string(url(try argument(2)).path), "trust": .bool(arguments.contains("--trust-local-code")), "interpreter": option("--interpreter").map(JSONValue.string) ?? .null]))
            case "configure": return try await client.call("apps.save", StrictJSON.decode(Data(contentsOf: url(try argument(2)))))
            case "uninstall": return try await client.call("apps.remove", .object(["id": .string(try argument(2)), "keepData": .bool(!arguments.contains("--delete-data"))]))
            case "disable":
                return try await client.call("apps.disable", .object(["id": .string(try argument(2))]))
            default: throw PlatformError.invalid(help)
            }
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
            if try argument(1) == "enable" { _ = try AgentSecurity.requirement(identifiers: ["com.ledge.agent"]); try service.register() } else if try argument(1) == "disable" { try await service.unregister() } else { throw PlatformError.invalid(help) }
            return .object(["serviceStatus": .number(Double(service.status.rawValue))])
        case "ui":
            guard try argument(1) == "open" else { throw PlatformError.invalid(help) }
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
            let candidate = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let appURL: URL?
            if candidate.pathExtension == "app" { appURL = candidate }
            else { appURL = await MainActor.run { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ledge.app") } }
            guard let appURL else { throw PlatformError.unavailable("Ledge app is not installed") }
            await MainActor.run { NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) }
            return .object(["requested": .bool(true)])
        case "dev", "test":
            let directory = url(try argument(1))
            let data = try Data(contentsOf: directory.appendingPathComponent("ledge-plugin.json"))
            let v2 = try StrictJSON.decode(data)["schemaVersion"].number == 2
            let app = v2 ? try PluginManifestV2.validated(data) : nil
            let legacy = v2 ? nil : try ManifestValidator.validate(data: data)
            let runtime = app?.runtime ?? legacy!.runtime
            let requested = option("--interpreter") ?? runtime.interpreter ?? directory.appendingPathComponent(runtime.entry).path
            let executable = requested.hasPrefix("/") ? requested : ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/", "/bin/"].map { $0 + requested }.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? ""
            let fixture: JSONValue = try option("--fixture").map { try StrictJSON.decode(Data(contentsOf: url($0))) } ?? .empty
            let config = fixture["config"].object == nil ? app?.defaultConfig ?? .empty : fixture["config"]
            if let schema = app?.configSchema { try PluginConfigSchema.validate(config, schema: StrictJSON.decode(Data(contentsOf: directory.appendingPathComponent(schema)))) }
            let selectedCommand = option("--command") ?? app?.defaultCommand ?? legacy!.defaultCommand
            let actionArguments = fixture["arguments"].object == nil ? JSONValue.empty : fixture["arguments"]
            try app?.validateCommand(selectedCommand, arguments: actionArguments)
            let result = try await ProgramRunner().execute(executable: executable, arguments: runtime.interpreter != nil || option("--interpreter") != nil ? [directory.appendingPathComponent(runtime.entry).path] : [], directory: directory, request: .object(["runID": .string("preview"), "automationID": .string("preview"), "config": config, "stateRevision": fixture["stateRevision"].number.map(JSONValue.number) ?? .number(0), "state": fixture["state"].object == nil ? .empty : fixture["state"], "arguments": actionArguments, "mode": .string("preview"), "now": fixture["now"].string.map(JSONValue.string) ?? .string(ISO8601DateFormatter().string(from: .now)), "hostProtocol": .string(v2 ? "2" : "1"), "command": .string(selectedCommand)]), timeout: 30) { method, params in
                if method == "host.state.get" { return fixture["state"].object == nil ? .empty : fixture["state"] }
                if method == "host.records.query" { return fixture["records"].array == nil ? .array([]) : fixture["records"] }
                let key = (params["operation"].string ?? "") + ":" + (params["params"]["repository"].string ?? "")
                guard let response = fixture["responses"].object?[key] else { throw PlatformError.unavailable("No fixture response for \(key); dev does not access live integrations") }
                return response
            }
            try result.viewSnapshot?.presentation.validate(instanceID: "preview")
            let value = try WireCoding.value(result)
            if let expected = fixture["expect"].object { for (key, expectation) in expected where value[key] != expectation { throw PlatformError.invalid("Fixture expectation failed for \(key)") } }
            return value
        case "init":
            let directory = url(try argument(1))
            guard !FileManager.default.fileExists(atPath: directory.path) else { throw PlatformError.invalid("Directory already exists") }
            let language = option("--language") ?? "python"
            guard ["python", "typescript"].contains(language) else { throw PlatformError.invalid("Use python or typescript") }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let entry = language == "python" ? "main.py" : "main.mjs"
            let interpreter = language == "python" ? "python3" : "node"
            let manifest = "{\"schemaVersion\":2,\"id\":\"dev.local.hello\",\"version\":\"0.1.0\",\"hostAPI\":\"2\",\"name\":\"Hello Ledge\",\"summary\":\"Your own notch app\",\"publisher\":\"Local developer\",\"runtime\":{\"kind\":\"command\",\"entry\":\"\(entry)\",\"interpreter\":\"\(interpreter)\"},\"capabilities\":[\"presentation.publish\"],\"commands\":[{\"id\":\"run\",\"title\":\"Run\"}],\"defaultCommand\":\"run\"}"
            try Data(manifest.utf8).write(to: directory.appendingPathComponent("ledge-plugin.json"))
            let program: String
            if language == "python" { program = "import json,sys\nr=json.loads(sys.stdin.readline()); p=r['params']\nprint(json.dumps({'jsonrpc':'2.0','id':r['id'],'result':{'viewSnapshot':{'presentation':{'protocolVersion':2,'instanceID':p['automationID'],'viewID':'main','revision':p.get('stateRevision',0)+1,'sensitivity':'public','root':{'id':'hello','kind':'text','text':'Hello from your app. Edit this program to make it useful.'}},'checkedAt':p['now']}}}),flush=True)\n" }
            else { program = "import {createInterface} from 'node:readline';\nconst lines=createInterface({input:process.stdin});\nlines.once('line',line=>{const r=JSON.parse(line),p=r.params; console.log(JSON.stringify({jsonrpc:'2.0',id:r.id,result:{viewSnapshot:{presentation:{protocolVersion:2,instanceID:p.automationID,viewID:'main',revision:(p.stateRevision??0)+1,sensitivity:'public',root:{id:'hello',kind:'text',text:'Hello from your app.'}},checkedAt:p.now}}})); lines.close(); process.stdin.destroy();});\n" }
            try Data(program.utf8).write(to: directory.appendingPathComponent(entry))
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
