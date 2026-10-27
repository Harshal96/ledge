import Foundation
import LedgeDomain

/// Legacy coordinator compatibility. Inactive in the plugin-only composition;
/// existing feature data is retained and no feature service starts here.
public struct AppEnvironment: Sendable {
    public typealias CandidateSnapshot = @Sendable () async -> [ActionCandidate]
    public let candidateSnapshot: CandidateSnapshot
    public let enabledFeatures: Set<FeatureID>
    public let presentationSafe: Bool
    public init(candidateSnapshot: @escaping CandidateSnapshot = { [] }, enabledFeatures: Set<FeatureID> = [], presentationSafe: Bool = false) { self.candidateSnapshot = candidateSnapshot; self.enabledFeatures = enabledFeatures; self.presentationSafe = presentationSafe }
    public static let live = AppEnvironment()
    public static let allServicesFailing = AppEnvironment()
}
