import AppKit
import Foundation
import LedgeDomain
import Observation
import ShellFeature

public struct StatusMenuState: Sendable, Equatable {
    public let canOpenSettings: Bool
    public let canQuit: Bool

    public init(canOpenSettings: Bool = true, canQuit: Bool = true) {
        self.canOpenSettings = canOpenSettings
        self.canQuit = canQuit
    }
}

/// Main-actor composition root. Feature services publish immutable candidates
/// into this coordinator; they do not know about one another or the panel.
@MainActor @Observable
public final class AppCoordinator {
    public private(set) var resolution: ActionResolution = .empty
    public private(set) var presentationSafe = false
    public private(set) var statusMenuState = StatusMenuState()
    public var onResolutionChanged: (@MainActor (ActionResolution) -> Void)?
    public var onRouteRequested: (@MainActor (ShelfRoute) -> Void)?

    private weak var panel: (any ShellPanelControlling)?
    private let environment: AppEnvironment
    private let resolver: ActionResolver
    private var candidatesByFeature: [FeatureID: [ActionCandidate]] = [:]
    private var dismissedIDs: Set<UUID> = []
    private var hasStarted = false

    public init(
        environment: AppEnvironment = .live,
        panel: (any ShellPanelControlling)? = nil,
        resolver: ActionResolver = ActionResolver()
    ) {
        self.environment = environment
        self.panel = panel
        self.resolver = resolver
    }

    /// Starts only non-permission work. Calendar, screen capture, pasteboard,
    /// and Core Audio adapters are intentionally injected later when their
    /// feature is invoked or enabled; a failed adapter cannot block recovery.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        presentationSafe = environment.presentationSafe
        let initialCandidates = await environment.candidateSnapshot()
        submit(initialCandidates)
        if presentationSafe { panel?.dismiss(reason: .presentationSafe) }
    }

    public func submit(_ candidates: [ActionCandidate]) {
        let grouped = Dictionary(grouping: candidates, by: \ActionCandidate.feature)
        for (feature, values) in grouped { candidatesByFeature[feature] = values }
        recompute()
    }

    public func replaceCandidates(_ candidates: [ActionCandidate], for feature: FeatureID) {
        candidatesByFeature[feature] = candidates
        recompute()
    }

    public func setEnabled(_ enabled: Bool, for feature: FeatureID) {
        var enabledFeatures = environment.enabledFeatures
        if enabled { enabledFeatures.insert(feature) } else { enabledFeatures.remove(feature) }
        // Keep the immutable environment boundary while allowing local
        // feature toggles for the running session.
        sessionEnabledFeatures = enabledFeatures
        recompute()
    }

    public func setPresentationSafe(_ enabled: Bool) {
        presentationSafe = enabled
        if enabled { panel?.dismiss(reason: .presentationSafe) }
        recompute()
    }

    public func dismissCurrentAction(_ candidateID: UUID? = nil) {
        if let candidateID {
            dismissedIDs.insert(candidateID)
        } else if let currentID = resolution.primary?.id {
            dismissedIDs.insert(currentID)
        }
        panel?.dismiss(reason: .actionCompleted)
        recompute()
    }

    /// Dispatches typed commands only. Commands that open an editor or a
    /// feature leave the shelf expanded; completed one-shot commands dismiss
    /// it and remember the candidate for this session.
    public func dispatch(_ candidate: ActionCandidate) {
        switch candidate.command {
        case .openQuickCapture:
            reveal(.quickCapture, reason: .userAction)
        case .searchClipboard:
            reveal(.searchClipboard, reason: .userAction)
        case .openAudioControls:
            reveal(.audioControls, reason: .userAction)
        case .openSettings:
            openSettings()
        case .openItem:
            reveal(.home, reason: .userAction)
            dismissCurrentAction(candidate.id)
        case let .joinMeeting(url):
            guard ExternalURLPolicy().validate(url.absoluteString).isSuccess else { return }
            guard NSWorkspace.shared.open(url) else { return }
            dismissCurrentAction(candidate.id)
        }
    }

    public func reveal(_ route: ShelfRoute, reason: RevealReason = .hotKey) {
        onRouteRequested?(route)
        panel?.reveal(route, reason: reason, screenID: nil)
    }

    public func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private var sessionEnabledFeatures: Set<FeatureID>?

    private func recompute() {
        let candidates = candidatesByFeature.values.flatMap { $0 }
        let enabled = sessionEnabledFeatures ?? environment.enabledFeatures
        resolution = resolver.resolve(
            candidates,
            now: .now,
            presentationSafe: presentationSafe,
            enabledFeatures: enabled,
            dismissedIDs: dismissedIDs
        )
        onResolutionChanged?(resolution)
    }
}
