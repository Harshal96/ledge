import Foundation
import LedgeDomain

public enum MeetingParticipation: String, Sendable, Equatable { case accepted, tentative, declined, none }
public enum MeetingStatus: String, Sendable, Equatable { case confirmed, cancelled }
public enum MeetingAccess: Sendable, Equatable { case notDetermined, authorized, denied }
public enum PresentationSafeMode: Sendable, Equatable { case off, manual, mirroredDisplay, externalDisplay }

public struct Meeting: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let participation: MeetingParticipation
    public let status: MeetingStatus
    public let url: String?
    public let location: String?
    public let notes: String?

    public init(id: String = UUID().uuidString, title: String, start: Date, end: Date, isAllDay: Bool = false, participation: MeetingParticipation = .none, status: MeetingStatus = .confirmed, url: String? = nil, location: String? = nil, notes: String? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.isAllDay = isAllDay
        self.participation = participation; self.status = status; self.url = url; self.location = location; self.notes = notes
    }

    public static func fixture(id: String = UUID().uuidString, title: String = "Planning", start: Date = .now, end: Date? = nil, isAllDay: Bool = false, participation: MeetingParticipation = .none, status: MeetingStatus = .confirmed, url: String? = nil, location: String? = nil, notes: String? = nil) -> Meeting {
        Meeting(id: id, title: title, start: start, end: end ?? start.addingTimeInterval(1_800), isAllDay: isAllDay, participation: participation, status: status, url: url, location: location, notes: notes)
    }
}

public struct MeetingSnapshot: Sendable, Equatable {
    public let access: MeetingAccess
    public let meetings: [Meeting]
    public let fetchedAt: Date?
    public init(access: MeetingAccess, meetings: [Meeting], fetchedAt: Date? = nil) { self.access = access; self.meetings = meetings; self.fetchedAt = fetchedAt }
    public static let empty = MeetingSnapshot(access: .notDetermined, meetings: [])
}

public struct JoinURL: Sendable, Equatable { public let url: URL; public let requiresConfirmation: Bool; public init(url: URL, requiresConfirmation: Bool) { self.url = url; self.requiresConfirmation = requiresConfirmation } }
public struct MeetingRenderState: Sendable, Equatable { public let title: String?; public let agenda: String?; public let countdown: String?; public let showsJoin: Bool; public let join: JoinURL?; public init(title: String?, agenda: String?, countdown: String?, showsJoin: Bool, join: JoinURL?) { self.title = title; self.agenda = agenda; self.countdown = countdown; self.showsJoin = showsJoin; self.join = join } }

public protocol MeetingProviding: Sendable { func requestAccess() async -> MeetingAccess; func refresh(now: Date) async -> MeetingSnapshot }
