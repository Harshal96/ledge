import Foundation
import LedgeDomain

/// The bounded set of actions that can be shown by the shelf at one time.
/// `all` is deliberately derived from the primary and secondaries so callers
/// cannot accidentally render a fourth action in peek state.
public struct ActionResolution: Sendable, Equatable {
    public let primary: ActionCandidate?
    public let secondary: [ActionCandidate]

    public init(primary: ActionCandidate?, secondary: [ActionCandidate] = []) {
        self.primary = primary
        self.secondary = Array(secondary.prefix(2))
    }

    public var all: [ActionCandidate] {
        (primary.map { [$0] } ?? []) + secondary
    }

    public static let empty = ActionResolution(primary: nil)
}

/// Compatibility spelling for clients that describe the result as a set of
/// resolved actions rather than a resolution operation.
public typealias ResolvedActions = ActionResolution

public struct ActionResolver: Sendable {
    private let featurePriority: [FeatureID: Int]

    public init(featurePriority: [FeatureID: Int]? = nil) {
        self.featurePriority = featurePriority ?? Self.defaultFeaturePriority
    }

    /// Applies privacy, expiry, dismissal, and feature-enable gates before a
    /// stable local sort. No content profiling or model inference is involved.
    public func resolve(
        _ candidates: [ActionCandidate],
        now: Date = .now,
        presentationSafe: Bool,
        enabledFeatures: Set<FeatureID> = Set(FeatureID.allCases),
        dismissedIDs: Set<UUID> = []
    ) -> ActionResolution {
        let eligible = candidates
            .filter { candidate in
                guard candidate.expiresAt.map({ $0 > now }) ?? true else { return false }
                guard !dismissedIDs.contains(candidate.id) else { return false }
                guard !presentationSafe || candidate.sensitivity == .public else { return false }
                // Recovery is content-free and remains available even when a
                // feature has been disabled or its service failed.
                guard candidate.feature == .recovery || enabledFeatures.contains(candidate.feature) else { return false }
                return true
            }
            .sorted(by: sort)

        if let primary = eligible.first {
            return ActionResolution(primary: primary, secondary: Array(eligible.dropFirst().prefix(2)))
        }

        // Quick Capture is the useful local fallback whenever it is enabled.
        if enabledFeatures.contains(.quickCapture) {
            return ActionResolution(primary: ActionCandidate(
                id: FixedActionID.quickCapture,
                feature: .quickCapture,
                title: "Quick Capture",
                urgency: .available,
                sensitivity: .public,
                command: .openQuickCapture
            ))
        }

        return ActionResolution(primary: ActionCandidate(
            id: FixedActionID.openSettings,
            feature: .recovery,
            title: "Open Settings",
            subtitle: "Review disabled features or permissions",
            urgency: .available,
            sensitivity: .public,
            command: .openSettings
        ))
    }

    private func sort(_ lhs: ActionCandidate, _ rhs: ActionCandidate) -> Bool {
        if lhs.urgency != rhs.urgency { return lhs.urgency > rhs.urgency }
        switch (lhs.dueAt, rhs.dueAt) {
        case let (left?, right?) where left != right: return left < right
        case (nil, .some): return false
        case (.some, nil): return true
        default: break
        }
        let leftPriority = featurePriority[lhs.feature] ?? Int.max
        let rightPriority = featurePriority[rhs.feature] ?? Int.max
        if leftPriority != rightPriority { return leftPriority < rightPriority }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static let defaultFeaturePriority: [FeatureID: Int] = [
        .meetings: 0,
        .handoff: 1,
        .quickCapture: 2,
        .clipboard: 3,
        .audio: 4,
        .screenshot: 5,
        .shell: 6,
        .recovery: 7
    ]
}
