import Foundation
import Testing
import AutomationDomain
@testable import NotificationRouting

@Test func quietHoursAndUserMuteOverridePluginUrgency() {
    let date = ISO8601DateFormatter().date(from: "2026-10-26T18:00:00Z")!
    let policy = DeliveryPolicy()
    let event = HostEvent(sourceKey: "one", title: "Hello", priority: 100)
    #expect(!policy.shouldPeek(event: event, preferences: .init(mode: "off"), now: date, timezone: "Asia/Kolkata"))
    #expect(!policy.shouldPeek(event: event, preferences: .init(mode: "immediate", quietHours: ["22:00", "08:00"]), now: date, timezone: "Asia/Kolkata"))
}
