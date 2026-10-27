import Foundation

public struct PluginCommandDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var argumentSchema: JSONValue?
    public var destructive: Bool?
}

public struct PluginManifestV2: Codable, Sendable, Equatable, Identifiable {
    public var schemaVersion: Int
    public var id: String
    public var version: String
    public var hostAPI: String
    public var name: String
    public var summary: String
    public var publisher: String
    public var runtime: PluginManifest.Runtime
    public var capabilities: [String]
    public var commands: [PluginCommandDefinition]
    public var defaultCommand: String
    public var configSchema: String?
    public var uiSchema: String?
    public var defaultConfig: JSONValue?
    public var providerDependencies: [String]?
    public var icon: String?

    public static func validated(_ data: Data) throws -> Self {
        let json = try StrictJSON.decode(data)
        try Validation.keys(json, allowed: ["schemaVersion", "id", "version", "hostAPI", "name", "summary", "publisher", "runtime", "capabilities", "commands", "defaultCommand", "configSchema", "uiSchema", "defaultConfig", "providerDependencies", "icon"])
        let manifest = try WireCoding.decoder().decode(Self.self, from: data)
        guard manifest.schemaVersion == 2, manifest.hostAPI == "2", Validation.identifier(manifest.id), manifest.id.contains("."),
              manifest.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
              !manifest.name.isEmpty, manifest.name.count <= 100, manifest.summary.count <= 1000, manifest.publisher.count <= 200,
              ["command", "service"].contains(manifest.runtime.kind), !manifest.commands.isEmpty, manifest.commands.count <= 32,
              Set(manifest.commands.map(\.id)).count == manifest.commands.count,
              manifest.commands.allSatisfy({ Validation.identifier($0.id) && !$0.title.isEmpty && $0.title.count <= 100 }),
              manifest.commands.contains(where: { $0.id == manifest.defaultCommand }),
              Set(manifest.capabilities).isSubset(of: ManifestValidator.capabilities.union(["presentation.publish", "command.execute", "connections.read"])) else { throw PlatformError.invalid("Invalid or unsupported plugin app manifest") }
        try Validation.keys(json["runtime"], allowed: ["kind", "entry", "interpreter"])
        try Validation.relativePath(manifest.runtime.entry)
        for path in [manifest.configSchema, manifest.uiSchema].compactMap({ $0 }) { try Validation.relativePath(path) }
        for command in json["commands"].array ?? [] { try Validation.keys(command, allowed: ["id", "title", "argumentSchema", "destructive"]) }
        return manifest
    }
    public func validateCommand(_ command: String, arguments: JSONValue) throws {
        guard let definition = commands.first(where: { $0.id == command }) else { throw PlatformError.denied("Undeclared app command") }
        if let schema = definition.argumentSchema { try PluginConfigSchema.validate(arguments, schema: schema, path: "arguments") }
        else if arguments != .empty { throw PlatformError.invalid("This command does not accept arguments") }
    }
    public func validateInvocation(_ command: String, arguments: JSONValue, confirmed: Bool) throws {
        try validateCommand(command, arguments: arguments)
        if commands.first(where: { $0.id == command })?.destructive == true && !confirmed { throw PlatformError.denied("This command requires explicit confirmation") }
    }
}

public struct PluginInstallation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var manifest: PluginManifestV2
    public var directory: URL
    public var executable: String
    public var arguments: [String]
    public var digest: String
    public var source: String
    public var publisherStatus: String
    public var grants: [String]
    public var installedAt: Date
    public init(manifest: PluginManifestV2, directory: URL, executable: String, arguments: [String], digest: String, source: String, publisherStatus: String = "local code — not publisher verified", grants: [String]) {
        id = manifest.id; self.manifest = manifest; self.directory = directory; self.executable = executable; self.arguments = arguments; self.digest = digest; self.source = source; self.publisherStatus = publisherStatus; self.grants = grants; installedAt = .now
    }
}

public struct PluginInstance: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var installationID: String
    public var name: String
    public var config: JSONValue
    public var connection: String?
    public var schedule: ScheduleSpec
    public var delivery: DeliveryPreferences
    public var enabled: Bool
    public var pinned: Bool
    public var revision: Int
    public var generation: Int
    public init(id: String = UUID().uuidString, installationID: String, name: String, config: JSONValue = .empty, connection: String? = nil, schedule: ScheduleSpec = .init(), delivery: DeliveryPreferences = .init(), enabled: Bool = false, pinned: Bool = false, revision: Int = 1, generation: Int = 1) {
        self.id = id; self.installationID = installationID; self.name = name; self.config = config; self.connection = connection; self.schedule = schedule; self.delivery = delivery; self.enabled = enabled; self.pinned = pinned; self.revision = revision; self.generation = generation
    }
}

public struct PluginLease: Codable, Sendable, Equatable {
    public let id: String
    public let instanceID: String
    public let installationID: String
    public let generation: Int
    public let revision: Int
    public init(instance: PluginInstance) { id = UUID().uuidString; instanceID = instance.id; installationID = instance.installationID; generation = instance.generation; revision = instance.revision }
}

public struct PluginActionRequest: Codable, Sendable {
    public let instanceID: String
    public let command: String
    public let arguments: JSONValue
    public let expectedRevision: Int
    public let viewRevision: Int?
    public let confirmed: Bool?
    public init(instanceID: String, command: String, arguments: JSONValue = .empty, expectedRevision: Int, viewRevision: Int? = nil, confirmed: Bool = false) { self.instanceID = instanceID; self.command = command; self.arguments = arguments; self.expectedRevision = expectedRevision; self.viewRevision = viewRevision; self.confirmed = confirmed }
}
