import Foundation

public struct PresentationRedactor: Sendable {
    public init() {}
    public func agendaPreview(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let plain = notes.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let lines = plain.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let result = lines.prefix(4).joined(separator: "\n")
        return result.isEmpty ? nil : String(result.prefix(1_000))
    }
    public func renderState(meeting: Meeting?, join: JoinURL?, now: Date, safeMode: PresentationSafeMode) -> MeetingRenderState {
        guard let meeting else { return MeetingRenderState(title: nil, agenda: nil, countdown: nil, showsJoin: false, join: nil) }
        let countdown = Self.countdown(until: meeting.start, now: now)
        if safeMode != .off { return MeetingRenderState(title: nil, agenda: nil, countdown: countdown, showsJoin: join != nil, join: join) }
        return MeetingRenderState(title: meeting.title, agenda: agendaPreview(meeting.notes), countdown: countdown, showsJoin: join != nil, join: join)
    }
    private static func countdown(until start: Date, now: Date) -> String { let seconds = max(0, Int(start.timeIntervalSince(now))); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
}
