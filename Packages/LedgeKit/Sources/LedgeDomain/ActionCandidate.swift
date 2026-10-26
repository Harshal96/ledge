import Foundation

public enum FeatureID: String, Codable, Sendable, CaseIterable {
    case shell, quickCapture, clipboard, meetings, handoff, screenshot, audio
    case recovery

    /// Short aliases keep the resolver contract readable at call sites while
    /// preserving the feature identifiers already persisted by earlier slices.
    public static var capture: FeatureID { .quickCapture }
    public static var meeting: FeatureID { .meetings }
}

public enum Sensitivity: String, Codable, Sendable, CaseIterable {
    case `public`
    case sensitive
}

public enum ActionUrgency: Int, Sendable, Codable, Comparable {
    case background = 0
    case available = 10
    case soon = 20
    case immediate = 30

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum ShelfCommand: Sendable, Equatable {
    case openQuickCapture
    case openSettings
    case openAudioControls
    case searchClipboard
    case openItem(UUID)
    case joinMeeting(URL)
}

public struct ActionCandidate: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let feature: FeatureID
    public let title: String
    public let subtitle: String?
    public let dueAt: Date?
    public let urgency: ActionUrgency
    public let sensitivity: Sensitivity
    public let command: ShelfCommand
    public let expiresAt: Date?

    public init(id: UUID, feature: FeatureID, title: String, subtitle: String? = nil, dueAt: Date? = nil, urgency: ActionUrgency, sensitivity: Sensitivity, command: ShelfCommand, expiresAt: Date? = nil) {
        self.id = id
        self.feature = feature
        self.title = title
        self.subtitle = subtitle
        self.dueAt = dueAt
        self.urgency = urgency
        self.sensitivity = sensitivity
        self.command = command
        self.expiresAt = expiresAt
    }

    /// A deterministic-test constructor used by feature fixtures and UI
    /// previews. Production candidates should provide their stable source ID.
    public static func fixture(
        id: UUID = UUID(),
        feature: FeatureID,
        title: String? = nil,
        subtitle: String? = nil,
        urgency: ActionUrgency,
        dueAt: Date? = nil,
        sensitivity: Sensitivity = .public,
        command: ShelfCommand? = nil,
        expiresAt: Date? = nil
    ) -> ActionCandidate {
        let resolvedCommand = command ?? defaultCommand(for: feature, id: id)
        return ActionCandidate(
            id: id,
            feature: feature,
            title: title ?? feature.displayName,
            subtitle: subtitle,
            dueAt: dueAt,
            urgency: urgency,
            sensitivity: sensitivity,
            command: resolvedCommand,
            expiresAt: expiresAt
        )
    }

    private static func defaultCommand(for feature: FeatureID, id: UUID) -> ShelfCommand {
        switch feature {
        case .quickCapture: .openQuickCapture
        case .clipboard: .searchClipboard
        case .meetings: .openSettings
        case .handoff, .screenshot, .shell: .openItem(id)
        case .audio: .openAudioControls
        case .recovery: .openSettings
        }
    }
}

public extension FeatureID {
    var displayName: String {
        switch self {
        case .shell: "Ledge"
        case .quickCapture: "Quick Capture"
        case .clipboard: "Search Clipboard"
        case .meetings: "Upcoming Meeting"
        case .handoff: "Handoff"
        case .screenshot: "Screenshot"
        case .audio: "Audio Controls"
        case .recovery: "Open Settings"
        }
    }
}

public enum FixedActionID {
    public static let quickCapture = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    public static let openSettings = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    public static let audioControls = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    public static let clipboardSearch = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
}
