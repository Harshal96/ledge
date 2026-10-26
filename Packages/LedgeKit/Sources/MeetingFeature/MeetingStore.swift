import Foundation
import Observation
import LedgeDomain

@MainActor @Observable public final class MeetingStore {
    public private(set) var snapshot: MeetingSnapshot = .empty
    public private(set) var safeMode: PresentationSafeMode = .off
    public private(set) var isVisible = false
    public private(set) var confirmationHost: String?
    public private(set) var sensitiveRevealUntil: Date?
    private let provider: any MeetingProviding
    private let selector: MeetingSelector
    private let parser: JoinURLParser
    public init(provider: any MeetingProviding, selector: MeetingSelector = MeetingSelector(), parser: JoinURLParser = JoinURLParser()) { self.provider = provider; self.selector = selector; self.parser = parser }
    public func requestCalendarAccess() async { snapshot = await provider.refresh(now: .now); if snapshot.access == .notDetermined { _ = await provider.requestAccess(); snapshot = await provider.refresh(now: .now) } }
    public func refresh(now: Date = .now) async { snapshot = await provider.refresh(now: now) }
    public func setVisible(_ visible: Bool) { isVisible = visible }
    public func setSafeMode(_ mode: PresentationSafeMode) { safeMode = mode }
    public func revealSensitiveContent(now: Date = .now) { sensitiveRevealUntil = now.addingTimeInterval(30) }
    public func countdownUpdateInterval(now: Date = .now) -> TimeInterval {
        guard isVisible, let meeting = selector.next(from: snapshot.meetings, now: now), meeting.start.timeIntervalSince(now) <= 5 * 60 else { return 60 }
        return 1
    }
    public func state(now: Date = .now) -> MeetingRenderState {
        let meeting = selector.next(from: snapshot.meetings, now: now)
        let join = meeting.flatMap(parser.joinURL)
        let effectiveSafeMode = (sensitiveRevealUntil ?? .distantPast) > now ? PresentationSafeMode.off : safeMode
        return PresentationRedactor().renderState(meeting: meeting, join: join, now: now, safeMode: effectiveSafeMode)
    }
    public func beginJoin(now: Date = .now) -> URL? { let state = state(now: now); guard let join = state.join else { return nil }; if join.requiresConfirmation { confirmationHost = join.url.host; return nil }; return join.url }
    public func confirmJoin() -> URL? { defer { confirmationHost = nil }; return confirmationHost.flatMap { host in selector.next(from: snapshot.meetings, now: .now).flatMap(parser.joinURL).flatMap { $0.url.host == host ? $0.url : nil } } }
    public func candidate(now: Date = .now) -> ActionCandidate? {
        guard let meeting = selector.next(from: snapshot.meetings, now: now) else { return nil }
        let secondsUntilStart = meeting.start.timeIntervalSince(now)
        let urgency: ActionUrgency = secondsUntilStart <= 10 * 60 ? .immediate : secondsUntilStart <= 30 * 60 ? .soon : .available
        let command = parser.joinURL(for: meeting).map { ShelfCommand.joinMeeting($0.url) } ?? .openSettings
        return ActionCandidate(
            id: stableCandidateID(for: meeting.id),
            feature: .meetings,
            title: safeMode == .off ? meeting.title : "Upcoming meeting",
            subtitle: parser.joinURL(for: meeting) == nil ? "No join link found" : "Join meeting",
            dueAt: meeting.start,
            urgency: urgency,
            sensitivity: .sensitive,
            command: command
        )
    }

    private func stableCandidateID(for value: String) -> UUID {
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 10_995_116_282_611_990_499
        for byte in value.utf8 {
            first ^= UInt64(byte); first &*= 1_099_511_628_211
            second ^= UInt64(byte &+ 17); second &*= 1_099_511_628_211
        }
        let hex = String(format: "%016llX%016llX", first, second)
        let chars = Array(hex)
        let uuid = "\(String(chars[0..<8]))-\(String(chars[8..<12]))-\(String(chars[12..<16]))-\(String(chars[16..<20]))-\(String(chars[20..<32]))"
        return UUID(uuidString: uuid) ?? FixedActionID.openSettings
    }
}
