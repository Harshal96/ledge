import Foundation

public struct MeetingSelector: Sendable {
    public init() {}
    public func next(from meetings: [Meeting], now: Date) -> Meeting? {
        meetings.filter { meeting in
            !meeting.isAllDay && meeting.status != .cancelled && meeting.participation != .declined && meeting.end > now
        }.min { $0.start < $1.start }
    }
}
