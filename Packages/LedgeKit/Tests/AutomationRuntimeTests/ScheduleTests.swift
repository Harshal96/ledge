import Foundation
import Testing
import AutomationDomain
@testable import AutomationRuntime

private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

@Test func cronUsesExplicitTimeZoneAndNextMinute() throws {
    let next = try CronSchedule("*/15 * * * *", timezone: "Asia/Kolkata").next(after: date("2026-10-26T04:31:00Z"))
    #expect(next == date("2026-10-26T04:45:00Z"))
    #expect(throws: (any Error).self) { try CronSchedule("* * * * * *", timezone: "UTC") }
    #expect(throws: (any Error).self) { try CronSchedule("*/0 * * * *", timezone: "UTC") }
    #expect(throws: (any Error).self) { try CronSchedule("65 * * * *", timezone: "UTC") }
}

@Test func cronSkipsSpringGapAndNeverRepeatsFoldMinute() throws {
    let spring = try CronSchedule("30 2 * * *", timezone: "America/New_York")
    #expect(try spring.next(after: date("2026-03-08T05:00:00Z")) == date("2026-03-09T06:30:00Z"))
    let fall = try CronSchedule("30 1 * * *", timezone: "America/New_York")
    #expect(try fall.next(after: date("2026-11-01T05:30:00Z")) == date("2026-11-02T06:30:00Z"))
}

@Test func cronDayOfMonthAndWeekdayUseOrAndSundayAlias() throws {
    let schedule = try CronSchedule("0 0 27 * 7", timezone: "UTC")
    #expect(try schedule.next(after: date("2026-10-26T00:00:00Z")) == date("2026-10-27T00:00:00Z"))
}

@Test func skippedMisfiresStillRunOnTimeAndIntervalsKeepTheirAnchor() throws {
    let due = date("2026-10-26T00:00:00Z")
    let skip = ScheduleSpec(intervalSeconds: 60, misfire: "skip")
    #expect(ScheduleEvaluator.shouldRun(skip, due: due, now: due.addingTimeInterval(1)))
    #expect(!ScheduleEvaluator.shouldRun(skip, due: due, now: due.addingTimeInterval(90)))
    #expect(try ScheduleEvaluator.nextAfterOccurrence(skip, due: due, now: due.addingTimeInterval(125)) == due.addingTimeInterval(180))
}

@Test func jitterIsStableBoundedAndDoesNotChangeOccurrenceIdentity() {
    let due = date("2026-10-26T00:00:00Z")
    let schedule = ScheduleSpec(intervalSeconds: 900, jitterSeconds: 60)
    let first = ScheduleEvaluator.executionDate(schedule, due: due, identity: "job/1")
    #expect(first == ScheduleEvaluator.executionDate(schedule, due: due, identity: "job/1"))
    #expect((0...60).contains(first.timeIntervalSince(due)))
}
