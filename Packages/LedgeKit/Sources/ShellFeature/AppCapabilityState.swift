import Foundation
import LedgeDomain

/// The small, feature-scoped set of states needed to present permission recovery.
///
/// `.allowed` is used by pasteboard APIs while `.authorized` is used by Apple's
/// protected-data APIs. They intentionally share the same granted semantics.
public enum CapabilityPermission: String, Codable, Equatable, Sendable, CaseIterable {
    case authorized
    case allowed
    case denied
    case notDetermined
    case unavailable

    public var isGranted: Bool { self == .authorized || self == .allowed }
    public var isDenied: Bool { self == .denied }
}

// These aliases keep the app and package vocabulary interchangeable without
// introducing another state enum that could drift from the capability model.
public typealias CapabilityStatus = CapabilityPermission
public typealias PermissionStatus = CapabilityPermission

/// A snapshot of independent capabilities. A denied capability only disables
/// the feature that needs it; shell and recovery stay available.
public struct AppCapabilityState: Codable, Equatable, Sendable {
    public let calendar: CapabilityPermission
    public let screenCapture: CapabilityPermission
    public let pasteboard: CapabilityPermission
    public let audio: CapabilityPermission

    public init(
        calendar: CapabilityPermission = .notDetermined,
        screenCapture: CapabilityPermission = .notDetermined,
        pasteboard: CapabilityPermission = .notDetermined,
        audio: CapabilityPermission = .allowed
    ) {
        self.calendar = calendar
        self.screenCapture = screenCapture
        self.pasteboard = pasteboard
        self.audio = audio
    }

    /// Whether the route can be offered without immediately asking for access.
    /// Quick Capture remains usable even if its optional screenshot capability
    /// is denied or has not been requested yet.
    public func isEnabled(_ feature: FeatureID) -> Bool {
        switch feature {
        case .meetings: calendar.isGranted
        case .screenshot: screenCapture.isGranted
        case .clipboard: pasteboard.isGranted
        case .audio: audio.isGranted
        case .shell, .quickCapture, .handoff, .recovery: true
        }
    }

    /// The permission relevant to a feature, if that feature has one.
    public func permission(for feature: FeatureID) -> CapabilityPermission? {
        switch feature {
        case .meetings: calendar
        case .screenshot: screenCapture
        case .clipboard: pasteboard
        case .audio: audio
        case .shell, .quickCapture, .handoff, .recovery: nil
        }
    }

    public func requiresPermission(for feature: FeatureID) -> Bool {
        permission(for: feature) != nil
    }

    /// Content-free values suitable for local diagnostics and support reports.
    /// No titles, URLs, bundle IDs, paths, or clipboard values are included.
    public var diagnosticValues: [String: String] {
        [
            "calendarAuthorized": String(calendar.isGranted),
            "screenCaptureAuthorized": String(screenCapture.isGranted),
            "pasteboardAuthorized": String(pasteboard.isGranted),
            "audioAuthorized": String(audio.isGranted),
            "recoveryAvailable": String(recoveryAvailable)
        ]
    }

    public var recoveryAvailable: Bool { true }
}
