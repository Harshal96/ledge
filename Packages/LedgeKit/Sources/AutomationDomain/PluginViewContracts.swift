import Foundation

public struct PluginViewNode: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var text: String?
    public var value: JSONValue?
    public var command: String?
    public var arguments: JSONValue?
    public var children: [PluginViewNode]?
    public init(id: String, kind: String, text: String? = nil, value: JSONValue? = nil, command: String? = nil, arguments: JSONValue? = nil, children: [PluginViewNode]? = nil) { self.id = id; self.kind = kind; self.text = text; self.value = value; self.command = command; self.arguments = arguments; self.children = children }
    public func validate() throws {
        var count = 0, ids = Set<String>()
        func visit(_ node: Self, depth: Int) throws {
            count += 1
            guard count <= 200, depth <= 8, Validation.identifier(node.id), ids.insert(node.id).inserted,
                  ["text", "markdown", "row", "section", "list", "badge", "progress", "button", "toggle", "selection", "form", "image"].contains(node.kind),
                  (node.text?.utf8.count ?? 0) <= 8192, (node.children?.count ?? 0) <= 100 else { throw PlatformError.invalid("Unsupported or oversized app view") }
            if let command = node.command, !Validation.identifier(command) { throw PlatformError.invalid("Invalid view command") }
            if node.kind == "image" { guard let handle = node.value?.string, Validation.identifier(handle) else { throw PlatformError.invalid("Images require a managed asset handle") } }
            if node.kind == "progress", let number = node.value?.number { guard number.isFinite, (0...1).contains(number) else { throw PlatformError.invalid("Progress must be between zero and one") } }
            for child in node.children ?? [] { try visit(child, depth: depth + 1) }
        }
        try visit(self, depth: 0)
    }
}

public struct PluginPresentation: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var instanceID: String
    public var viewID: String
    public var revision: Int
    public var sensitivity: String
    public var compactSummary: String?
    public var root: PluginViewNode
    public init(instanceID: String, root: PluginViewNode, revision: Int = 1, compactSummary: String? = nil, sensitivity: String = "sensitive") { protocolVersion = 2; self.instanceID = instanceID; viewID = "main"; self.revision = revision; self.sensitivity = sensitivity; self.compactSummary = compactSummary; self.root = root }
    public func validate(instanceID: String) throws {
        guard protocolVersion == 2, self.instanceID == instanceID, Validation.identifier(viewID), revision > 0, ["public", "sensitive"].contains(sensitivity), (compactSummary?.utf8.count ?? 0) <= 512 else { throw PlatformError.invalid("Invalid or foreign presentation") }
        try root.validate()
    }
}

public struct PluginViewSnapshot: Codable, Sendable, Equatable {
    public var presentation: PluginPresentation
    public var checkedAt: Date
    public var staleAfter: Date?
    public init(presentation: PluginPresentation, checkedAt: Date = .now, staleAfter: Date? = nil) { self.presentation = presentation; self.checkedAt = checkedAt; self.staleAfter = staleAfter }
}

public struct RunResultV2: Codable, Sendable {
    public var events: [HostEvent]?
    public var state: JSONValue?
    public var recordMutations: [PluginRecord]?
    public var summary: String?
    public var viewSnapshot: PluginViewSnapshot?
    public init(events: [HostEvent] = [], state: JSONValue? = nil, recordMutations: [PluginRecord] = [], summary: String? = nil, viewSnapshot: PluginViewSnapshot? = nil) { self.events = events; self.state = state; self.recordMutations = recordMutations; self.summary = summary; self.viewSnapshot = viewSnapshot }
    public var legacyResult: RunResult { .init(events: events ?? [], state: state, recordMutations: recordMutations ?? [], summary: summary) }
}

public struct ServiceCheckpoint: Codable, Sendable {
    public var id: String
    public var sequence: Int
    public var expectedStateRevision: Int
    public var result: RunResultV2
    public init(id: String = UUID().uuidString, sequence: Int, expectedStateRevision: Int, result: RunResultV2) { self.id = id; self.sequence = sequence; self.expectedStateRevision = expectedStateRevision; self.result = result }
}
public struct CommitReceipt: Codable, Sendable, Equatable {
    public var checkpointID: String
    public var stateRevision: Int
    public init(checkpointID: String, stateRevision: Int) { self.checkpointID = checkpointID; self.stateRevision = stateRevision }
}
