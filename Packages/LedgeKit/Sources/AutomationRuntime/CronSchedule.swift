import Foundation
import AutomationDomain

public struct CronSchedule: Sendable {
    private let fields: [Set<Int>]
    private let dayWildcard: Bool
    private let weekWildcard: Bool
    private let calendar: Calendar

    public init(_ expression: String, timezone: String) throws {
        let parts = expression.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5, let zone = TimeZone(identifier: timezone) else { throw PlatformError.invalid("Use five-field cron and an IANA timezone") }
        fields = try zip(parts, [0...59, 0...23, 1...31, 1...12, 0...7]).map { try Self.field($0, range: $1) }
        dayWildcard = parts[2] == "*"; weekWildcard = parts[4] == "*"
        var c = Calendar(identifier: .gregorian); c.timeZone = zone; calendar = c
    }

    public func next(after date: Date) throws -> Date {
        // Enumerate by local day. Calendar resolves DST and avoids minute-by-minute
        // scans over years for sparse expressions such as leap-day schedules.
        let start = calendar.startOfDay(for: date)
        for offset in 0..<(366 * 8) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let dc = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
            guard fields[3].contains(dc.month!) else { continue }
            let dom = fields[2].contains(dc.day!)
            let dow = fields[4].contains(dc.weekday! - 1) || (dc.weekday == 1 && fields[4].contains(7))
            let dayMatches = dayWildcard ? dow : weekWildcard ? dom : (dom || dow)
            guard dayMatches else { continue }
            for hour in fields[1].sorted() {
                for minute in fields[0].sorted() {
                    var components = dc; components.weekday = nil; components.hour = hour; components.minute = minute; components.second = 0
                    guard let candidate = calendar.nextDate(after: day.addingTimeInterval(-1), matching: components, matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward), calendar.isDate(candidate, inSameDayAs: day), candidate > date else { continue }
                    return candidate
                }
            }
        }
        throw PlatformError.invalid("Cron has no occurrence in the next eight years")
    }

    private static func field(_ expression: String, range: ClosedRange<Int>) throws -> Set<Int> {
        var values = Set<Int>()
        for item in expression.split(separator: ",", omittingEmptySubsequences: false) {
            let stepParts = item.split(separator: "/", omittingEmptySubsequences: false)
            guard (1...2).contains(stepParts.count) else { throw PlatformError.invalid("Invalid cron step") }
            let step = stepParts.count == 2 ? Int(stepParts[1]) : 1
            guard let step, step > 0, step <= range.upperBound + 1 else { throw PlatformError.invalid("Invalid cron step") }
            let bounds: ClosedRange<Int>
            if stepParts[0] == "*" { bounds = range }
            else {
                let limits = stepParts[0].split(separator: "-", omittingEmptySubsequences: false)
                guard (1...2).contains(limits.count), let a = Int(limits[0]), let b = Int(limits.last!), a <= b, range.contains(a), range.contains(b) else { throw PlatformError.invalid("Invalid cron range") }
                bounds = a...b
            }
            values.formUnion(stride(from: bounds.lowerBound, through: bounds.upperBound, by: step))
        }
        guard !values.isEmpty else { throw PlatformError.invalid("Empty cron field") }; return values
    }
}

public enum ScheduleEvaluator {
    public static func executionDate(_ schedule: ScheduleSpec, due: Date, identity: String) -> Date {
        var hash: UInt64 = 14695981039346656037
        for byte in "\(identity)/\(Int(due.timeIntervalSince1970))".utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let maximum = max(0, min(60, schedule.jitterSeconds))
        return due.addingTimeInterval(Double(hash % UInt64(maximum + 1)))
    }
    /// A small wake-up tolerance is not a misfire. Older occurrences are
    /// collapsed to one run only when the explicit catch-up policy permits it.
    public static func shouldRun(_ schedule: ScheduleSpec, due: Date, now: Date) -> Bool {
        let lateness = now.timeIntervalSince(due)
        return lateness >= 0 && (lateness <= 5 || (schedule.misfire == "run-latest" && lateness <= 86_400))
    }
    public static func nextAfterOccurrence(_ schedule: ScheduleSpec, due: Date, now: Date) throws -> Date? {
        if let interval = schedule.intervalSeconds {
            let step = Double(interval)
            return due.addingTimeInterval(max(1, floor(now.timeIntervalSince(due) / step) + 1) * step)
        }
        return try next(schedule, after: now)
    }
    public static func validate(_ schedule: ScheduleSpec) throws {
        if let cron = schedule.cron { _ = try CronSchedule(cron, timezone: schedule.timezone) }
        if let interval = schedule.intervalSeconds, interval < 60 { throw PlatformError.invalid("Minimum interval is 60 seconds") }
    }
    public static func next(_ schedule: ScheduleSpec, after date: Date) throws -> Date? {
        try validate(schedule)
        if let cron = schedule.cron { return try CronSchedule(cron, timezone: schedule.timezone).next(after: date) }
        return schedule.intervalSeconds.map { date.addingTimeInterval(Double($0)) }
    }
}
