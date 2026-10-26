import Foundation
import AutomationDomain

public struct DeliveryPolicy: Sendable {
    public init() {}
    public func shouldPeek(event: HostEvent, preferences: DeliveryPreferences, now: Date, timezone: String, presentationSafe: Bool = false, externalDisplay: Bool = false) -> Bool {
        guard ["digest", "immediate"].contains(preferences.mode), !presentationSafe, !(externalDisplay && event.sensitivity != "public") else { return false }
        if let hours = preferences.quietHours, hours.count == 2 {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timezone) ?? .gmt
            let parts = calendar.dateComponents([.hour, .minute], from: now); let minute = parts.hour! * 60 + parts.minute!
            func minutes(_ s: String) -> Int { let v = s.split(separator: ":").compactMap { Int($0) }; return v.count == 2 ? v[0] * 60 + v[1] : 0 }
            let start = minutes(hours[0]), end = minutes(hours[1])
            if start == end || (start < end ? (start..<end).contains(minute) : minute >= start || minute < end) { return false }
        }
        return true
    }
}

public struct PeekBudget: Sendable {
    private var deliveries: [Date] = []
    public init() {}
    public mutating func consume(now: Date) -> Bool {
        deliveries.removeAll { now.timeIntervalSince($0) >= 600 }
        guard deliveries.count < 3, deliveries.last.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return false }
        deliveries.append(now); return true
    }
}
