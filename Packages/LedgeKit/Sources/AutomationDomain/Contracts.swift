import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .object(v): try c.encode(v)
        case let .array(v): try c.encode(v)
        case let .string(v): try c.encode(v)
        case let .number(v): try c.encode(v)
        case let .bool(v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue { if case let .object(v) = self { return v[key] ?? .null }; return .null }
    public var string: String? { if case let .string(v) = self { return v }; return nil }
    public var object: [String: JSONValue]? { if case let .object(v) = self { return v }; return nil }
    public var array: [JSONValue]? { if case let .array(v) = self { return v }; return nil }
    public var bool: Bool? { if case let .bool(v) = self { return v }; return nil }
    public var number: Double? { if case let .number(v) = self { return v }; return nil }
    public static let empty = JSONValue.object([:])
}

public enum PlatformError: Error, LocalizedError, Sendable {
    case invalid(String), denied(String), unavailable(String), timeout, cancelled
    public var errorDescription: String? {
        switch self {
        case let .invalid(v), let .denied(v), let .unavailable(v): v
        case .timeout: "The program exceeded its execution deadline."
        case .cancelled: "Execution was cancelled."
        }
    }
}

public enum WireCoding {
    public static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }
    public static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    public static func value<T: Encodable>(_ object: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: encoder().encode(object)) }
}

public struct PluginManifest: Codable, Sendable, Equatable {
    public struct Runtime: Codable, Sendable, Equatable { public let kind: String; public let entry: String; public let interpreter: String? }
    public let schemaVersion: Int
    public let id: String
    public let version: String
    public let hostProtocol: String
    public let name: String
    public let runtime: Runtime
    public let capabilities: [String]
    public let configSchema: String?
    public let commands: [String]
    public let defaultCommand: String
}

public struct ScheduleSpec: Codable, Sendable, Equatable {
    public var cron: String?
    public var intervalSeconds: Int?
    public var timezone: String
    public var misfire: String
    public var jitterSeconds: Int
    public init(cron: String? = nil, intervalSeconds: Int? = nil, timezone: String = "UTC", misfire: String = "run-latest", jitterSeconds: Int = 0) {
        self.cron = cron; self.intervalSeconds = intervalSeconds; self.timezone = timezone; self.misfire = misfire; self.jitterSeconds = jitterSeconds
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cron = try c.decodeIfPresent(String.self, forKey: .cron); intervalSeconds = try c.decodeIfPresent(Int.self, forKey: .intervalSeconds)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone) ?? "UTC"
        misfire = try c.decodeIfPresent(String.self, forKey: .misfire) ?? "run-latest"
        jitterSeconds = try c.decodeIfPresent(Int.self, forKey: .jitterSeconds) ?? 0
    }
}

public struct DeliveryPreferences: Codable, Sendable, Equatable {
    public var surface: String
    public var mode: String
    public var quietHours: [String]?
    public init(surface: String = "notch", mode: String = "digest", quietHours: [String]? = nil) { self.surface = surface; self.mode = mode; self.quietHours = quietHours }
}

public struct AutomationDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var plugin: String
    public var command: String
    public var connection: String?
    public var schedule: ScheduleSpec
    public var enabled: Bool
    public var config: JSONValue
    public var delivery: DeliveryPreferences
    public var revision: Int
    public var timeoutSeconds: Int
    public init(id: String, plugin: String, command: String = "scan", connection: String? = nil, schedule: ScheduleSpec = .init(), enabled: Bool = false, config: JSONValue = .empty, delivery: DeliveryPreferences = .init(), revision: Int = 1, timeoutSeconds: Int = 120) {
        self.id = id; self.plugin = plugin; self.command = command; self.connection = connection; self.schedule = schedule; self.enabled = enabled; self.config = config; self.delivery = delivery; self.revision = revision; self.timeoutSeconds = timeoutSeconds
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); plugin = try c.decode(String.self, forKey: .plugin); command = try c.decode(String.self, forKey: .command)
        connection = try c.decodeIfPresent(String.self, forKey: .connection); schedule = try c.decodeIfPresent(ScheduleSpec.self, forKey: .schedule) ?? .init()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false; config = try c.decodeIfPresent(JSONValue.self, forKey: .config) ?? .empty
        delivery = try c.decodeIfPresent(DeliveryPreferences.self, forKey: .delivery) ?? .init(); revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        timeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 120
    }
}

public struct CardAction: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let url: String?
    public let command: String?
    public let arguments: JSONValue?
    public init(id: String, label: String, url: String? = nil, command: String? = nil, arguments: JSONValue? = nil) { self.id = id; self.label = label; self.url = url; self.command = command; self.arguments = arguments }
}

public struct HostEvent: Codable, Sendable, Equatable {
    public var sourceKey: String
    public var revision: Int
    public var title: String
    public var body: String
    public var sensitivity: String
    public var priority: Int
    public var actions: [CardAction]
    public var evidence: [String]
    public init(sourceKey: String, title: String, body: String = "", revision: Int = 1, sensitivity: String = "sensitive", priority: Int = 10, actions: [CardAction] = [], evidence: [String] = []) {
        self.sourceKey = sourceKey; self.title = title; self.body = body; self.revision = revision; self.sensitivity = sensitivity; self.priority = priority; self.actions = actions; self.evidence = evidence
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceKey = try c.decode(String.self, forKey: .sourceKey); title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""; revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        sensitivity = try c.decodeIfPresent(String.self, forKey: .sensitivity) ?? "sensitive"; priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 10
        actions = try c.decodeIfPresent([CardAction].self, forKey: .actions) ?? []; evidence = try c.decodeIfPresent([String].self, forKey: .evidence) ?? []
    }
}

public struct PluginRecord: Codable, Sendable, Equatable {
    public let collection: String
    public let key: String
    public let value: JSONValue?
    public init(collection: String, key: String, value: JSONValue?) { self.collection = collection; self.key = key; self.value = value }
}

public struct RunResult: Codable, Sendable {
    public var events: [HostEvent]
    public var state: JSONValue?
    public var recordMutations: [PluginRecord]
    public var summary: String?
    public var viewSnapshot: PluginViewSnapshot?
    public init(events: [HostEvent] = [], state: JSONValue? = nil, recordMutations: [PluginRecord] = [], summary: String? = nil, viewSnapshot: PluginViewSnapshot? = nil) { self.events = events; self.state = state; self.recordMutations = recordMutations; self.summary = summary; self.viewSnapshot = viewSnapshot }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events = try c.decodeIfPresent([HostEvent].self, forKey: .events) ?? []; state = try c.decodeIfPresent(JSONValue.self, forKey: .state)
        recordMutations = try c.decodeIfPresent([PluginRecord].self, forKey: .recordMutations) ?? []; summary = try c.decodeIfPresent(String.self, forKey: .summary)
        viewSnapshot = try c.decodeIfPresent(PluginViewSnapshot.self, forKey: .viewSnapshot)
    }
}

public struct InboxEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let automationID: String
    public let event: HostEvent
    public let createdAt: Date
    public let unread: Bool
    public init(id: String, automationID: String, event: HostEvent, createdAt: Date, unread: Bool = true) { self.id = id; self.automationID = automationID; self.event = event; self.createdAt = createdAt; self.unread = unread }
}

public struct RunRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let automationID: String
    public let occurrence: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let outcome: String
    public let summary: String?
    public init(id: String, automationID: String, occurrence: String, startedAt: Date, finishedAt: Date? = nil, outcome: String = "running", summary: String? = nil) { self.id = id; self.automationID = automationID; self.occurrence = occurrence; self.startedAt = startedAt; self.finishedAt = finishedAt; self.outcome = outcome; self.summary = summary }
}
