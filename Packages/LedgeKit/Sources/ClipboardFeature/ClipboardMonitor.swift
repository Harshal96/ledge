import Foundation
import LedgeDomain

public protocol ActiveApplicationProviding: Sendable { func activationBundleIDs() async -> (previous: String?, current: String?) }
public enum ClipboardPauseReason: Sendable, Equatable { case user, sessionLocked, asleep, accessDenied, awaitingAccess }

public actor ClipboardMonitor {
    public nonisolated let normalPollInterval: TimeInterval = 1
    public nonisolated let lowPowerPollInterval: TimeInterval = 2
    public nonisolated let timerTolerance: TimeInterval = 0.2
    public private(set) var watermark = 0
    public private(set) var pauseReason: ClipboardPauseReason? = .awaitingAccess
    private var optedIn = false
    private var selfWriteWatermark: Int?
    private let pasteboard: any PasteboardClient; private let activeApps: any ActiveApplicationProviding; private let policy: ClipboardPolicy; private let repository: any ShelfRepository
    public init(pasteboard: any PasteboardClient, activeApps: any ActiveApplicationProviding, policy: ClipboardPolicy, repository: any ShelfRepository) { self.pasteboard = pasteboard; self.activeApps = activeApps; self.policy = policy; self.repository = repository }
    public func setOptedIn(_ enabled: Bool) async { optedIn = enabled; if !enabled { pauseReason = .awaitingAccess } else { await refreshAccessState() } }
    public func setUserPaused(_ paused: Bool) { pauseReason = paused ? .user : nil }
    public func setSessionLocked(_ locked: Bool) { pauseReason = locked ? .sessionLocked : nil }
    public func setSleeping(_ sleeping: Bool) { pauseReason = sleeping ? .asleep : nil }
    public func grantAccessFromUserGesture() async -> PasteboardAccessState { guard optedIn else { return await pasteboard.accessState }; let state = await pasteboard.userInitiatedAccessProbe(); await refreshAccessState(); return state }
    public func pollOnce(now: Date = .now) async {
        let count = await pasteboard.changeCount
        guard count != watermark else { return }
        defer { watermark = count }
        guard optedIn, pauseReason == nil else { return }
        let state = await pasteboard.accessState
        guard state == .alwaysAllow || state == .legacyUnavailable else { pauseReason = state == .alwaysDeny ? .accessDenied : .awaitingAccess; return }
        if selfWriteWatermark == count { selfWriteWatermark = nil; return }
        let apps = await activeApps.activationBundleIDs()
        guard policy.sourceDecision(previousBundleID: apps.previous, currentBundleID: apps.current) == .allow else { return }
        let types = await pasteboard.declaredTypes
        guard policy.decision(previousBundleID: apps.previous, currentBundleID: apps.current, declaredTypes: types) == .allow else { return }
        let value: ClipboardValue?
        if types.contains(.string), let text = await pasteboard.readText(maximumUTF8Bytes: ClipboardPolicy.maximumContentUTF8Bytes) { value = .text(text) }
        else if types.contains(.url), let url = await pasteboard.readURL() { value = .url(url) }
        else { value = nil }
        guard let value, case .success(let draft) = policy.makeDraft(value, now: now) else { return }
        _ = try? await repository.insert(draft)
    }
    public func writeSelection(_ value: ClipboardValue) async { selfWriteWatermark = await pasteboard.write(value); watermark = selfWriteWatermark ?? watermark }
    private func refreshAccessState() async { guard optedIn else { return }; let state = await pasteboard.accessState; pauseReason = (state == .alwaysAllow || state == .legacyUnavailable) ? nil : (state == .alwaysDeny ? .accessDenied : .awaitingAccess) }
}
