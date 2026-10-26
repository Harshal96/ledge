import Foundation
import EventKit

public actor EventKitMeetingService: MeetingProviding {
    private let eventStore = EKEventStore()
    private var snapshot = MeetingSnapshot.empty
    public init() {}
    public func requestAccess() async -> MeetingAccess {
        do { return try await eventStore.requestFullAccessToEvents() ? .authorized : .denied } catch { return .denied }
    }
    public func refresh(now: Date) async -> MeetingSnapshot {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else { snapshot = MeetingSnapshot(access: status == .notDetermined ? .notDetermined : .denied, meetings: []); return snapshot }
        let end = now.addingTimeInterval(24 * 60 * 60)
        let predicate = eventStore.predicateForEvents(withStart: now, end: end, calendars: nil)
        snapshot = MeetingSnapshot(access: .authorized, meetings: eventStore.events(matching: predicate).map(Meeting.init(event:)), fetchedAt: now)
        return snapshot
    }
    public func authorizationRevoked() { snapshot = MeetingSnapshot(access: .denied, meetings: []) }
    public func eventStoreDidChange(now: Date) async { _ = await refresh(now: now) }
    public func systemDidWake(now: Date) async { _ = await refresh(now: now) }
    public func timeZoneDidChange(now: Date) async { _ = await refresh(now: now) }
    public func dayDidRollover(now: Date) async { _ = await refresh(now: now) }
}

private extension Meeting {
    init(event: EKEvent) {
        let participation: MeetingParticipation
        switch event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus { case .accepted: participation = .accepted; case .declined: participation = .declined; case .tentative: participation = .tentative; default: participation = .none }
        self.init(id: event.eventIdentifier, title: event.title ?? "Untitled meeting", start: event.startDate, end: event.endDate, isAllDay: event.isAllDay, participation: participation, status: event.status == .canceled ? .cancelled : .confirmed, url: event.url?.absoluteString, location: event.location, notes: event.notes)
    }
}
