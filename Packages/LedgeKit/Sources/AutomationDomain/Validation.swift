import Foundation

/// Validates JSON before JSONDecoder can erase duplicate keys. Escaped keys are
/// compared after decoding, so `id` and `\u0069d` cannot alias silently.
public enum StrictJSON {
    public static func decode(_ data: Data, maximumBytes: Int = 1_048_576) throws -> JSONValue {
        guard data.count <= maximumBytes else { throw PlatformError.invalid("JSON exceeds message budget") }
        var parser = JSONStructure(bytes: Array(data)); try parser.value(depth: 0); parser.space()
        guard parser.index == parser.bytes.count else { throw PlatformError.invalid("Trailing JSON data") }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

private struct JSONStructure {
    let bytes: [UInt8]; var index = 0
    mutating func space() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    mutating func take(_ byte: UInt8) -> Bool { space(); if index < bytes.count && bytes[index] == byte { index += 1; return true }; return false }
    mutating func string() throws -> String {
        space(); let start = index
        guard take(34) else { throw PlatformError.invalid("Expected a JSON string") }
        var escaped = false
        while index < bytes.count {
            let b = bytes[index]; index += 1
            if b == 34 && !escaped { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
            if b == 92 && !escaped { escaped = true } else { escaped = false }
        }
        throw PlatformError.invalid("Unterminated JSON string")
    }
    mutating func value(depth: Int) throws {
        guard depth < 32 else { throw PlatformError.invalid("JSON nesting exceeds 32") }
        space(); guard index < bytes.count else { throw PlatformError.invalid("Missing JSON value") }
        if bytes[index] == 34 { _ = try string(); return }
        if take(123) {
            var keys = Set<String>(); if take(125) { return }
            repeat {
                let key = try string(); guard keys.insert(key).inserted else { throw PlatformError.invalid("Duplicate JSON key: \(key)") }
                guard take(58) else { throw PlatformError.invalid("Missing colon") }; try value(depth: depth + 1)
                if take(125) { return }
            } while take(44)
            throw PlatformError.invalid("Malformed JSON object")
        }
        if take(91) {
            if take(93) { return }
            repeat { try value(depth: depth + 1); if take(93) { return } } while take(44)
            throw PlatformError.invalid("Malformed JSON array")
        }
        let start = index
        while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
        guard index > start else { throw PlatformError.invalid("Invalid JSON token") }
        _ = try JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: [.fragmentsAllowed])
    }
}

public enum ManifestValidator {
    public static let capabilities: Set<String> = ["events.publish", "state.readwrite", "github.issues.read", "github.pullRequests.read"]
    public static func validate(data: Data) throws -> PluginManifest {
        let value = try StrictJSON.decode(data)
        try Validation.keys(value, allowed: ["$schema", "schemaVersion", "id", "version", "hostProtocol", "name", "runtime", "capabilities", "configSchema", "commands", "defaultCommand"])
        try Validation.keys(value["runtime"], allowed: ["kind", "entry", "interpreter"])
        let m = try JSONDecoder().decode(PluginManifest.self, from: data)
        guard m.schemaVersion == 1, m.hostProtocol == "1", m.runtime.kind == "local.command", Validation.identifier(m.id), !m.name.isEmpty,
              m.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
              !m.commands.isEmpty, Set(m.commands).count == m.commands.count, m.commands.allSatisfy(Validation.identifier), m.commands.contains(m.defaultCommand),
              Set(m.capabilities).isSubset(of: capabilities) else { throw PlatformError.invalid("Unsupported or malformed plugin manifest") }
        try Validation.relativePath(m.runtime.entry)
        if let schema = m.configSchema { try Validation.relativePath(schema) }
        return m
    }
}

public enum ConfigurationValidator {
    public static func validate(data: Data) throws -> [AutomationDefinition] {
        let value = try StrictJSON.decode(data)
        try Validation.keys(value, allowed: ["schemaVersion", "automations"])
        guard value["schemaVersion"].number == 1, let values = value["automations"].array, values.count <= 100 else { throw PlatformError.invalid("Invalid automation configuration") }
        var ids = Set<String>()
        return try values.map { value in
            try Validation.keys(value, allowed: ["id", "plugin", "command", "connection", "schedule", "enabled", "config", "delivery", "revision", "timeoutSeconds"])
            try Validation.keys(value["schedule"], allowed: ["cron", "intervalSeconds", "timezone", "misfire", "jitterSeconds"], optional: true)
            try Validation.keys(value["delivery"], allowed: ["surface", "mode", "quietHours"], optional: true)
            let job = try JSONDecoder().decode(AutomationDefinition.self, from: JSONEncoder().encode(value))
            guard Validation.identifier(job.id), ids.insert(job.id).inserted, Validation.identifier(job.command), job.plugin.split(separator: "@").count == 2,
                  job.revision > 0, (5...900).contains(job.timeoutSeconds), TimeZone(identifier: job.schedule.timezone) != nil,
                  ["skip", "run-latest"].contains(job.schedule.misfire), (0...60).contains(job.schedule.jitterSeconds),
                  ["off", "inbox", "digest", "immediate"].contains(job.delivery.mode), job.delivery.surface == "notch" else { throw PlatformError.invalid("Invalid automation identity, schedule or delivery") }
            if let interval = job.schedule.intervalSeconds, interval < 60 { throw PlatformError.invalid("Minimum interval is 60 seconds") }
            if job.schedule.cron != nil && job.schedule.intervalSeconds != nil { throw PlatformError.invalid("Choose cron or interval") }
            if let cron = job.schedule.cron, cron.split(separator: " ").count != 5 { throw PlatformError.invalid("Cron requires five fields") }
            if let connection = job.connection, !Validation.identifier(connection) { throw PlatformError.invalid("Use a connection name, never a token") }
            if let hours = job.delivery.quietHours { guard hours.count == 2, hours.allSatisfy({ $0.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil }) else { throw PlatformError.invalid("Quiet hours must be HH:mm") } }
            return job
        }
    }
}

public enum Validation {
    public static func identifier(_ value: String) -> Bool { value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#, options: .regularExpression) != nil }
    public static func relativePath(_ value: String) throws {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"), !value.contains("\0"), !value.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0.isEmpty }) else { throw PlatformError.invalid("Entry must be contained in the plugin directory") }
    }
    public static func keys(_ value: JSONValue, allowed: Set<String>, optional: Bool = false) throws {
        if optional && value == .null { return }
        guard let object = value.object, Set(object.keys).isSubset(of: allowed) else { throw PlatformError.invalid("Unexpected or missing object fields") }
    }
}

extension HostEvent {
    public static func validated(data: Data) throws -> HostEvent {
        let value = try StrictJSON.decode(data)
        try Validation.keys(value, allowed: ["sourceKey", "revision", "title", "body", "sensitivity", "priority", "actions", "evidence"])
        for action in value["actions"].array ?? [] { try Validation.keys(action, allowed: ["id", "label", "url", "command", "arguments"]) }
        let e = try WireCoding.decoder().decode(HostEvent.self, from: data)
        guard !e.sourceKey.isEmpty, e.sourceKey.utf8.count <= 256, !e.title.isEmpty, e.title.utf8.count <= 512, e.body.utf8.count <= 8192,
              ["public", "sensitive"].contains(e.sensitivity), e.actions.count <= 3, Set(e.actions.map(\.id)).count == e.actions.count else { throw PlatformError.invalid("Invalid event/card limits") }
        for a in e.actions {
            guard Validation.identifier(a.id), !a.label.isEmpty, (a.url == nil) != (a.command == nil) else { throw PlatformError.invalid("Action must declare one URL or command") }
            if let url = a.url { guard let u = URLComponents(string: url), u.scheme == "https", u.host != nil, u.user == nil, u.password == nil else { throw PlatformError.invalid("Only HTTPS action URLs are supported") } }
        }
        return e
    }
}
