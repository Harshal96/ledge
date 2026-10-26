import Foundation
import Testing
import AutomationDomain
@testable import AutomationStorage

@Test func completionIsAtomicAndEventsAreDeduplicatedAcrossRestart() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let key = Data(repeating: 42, count: 32)
    let store = try SQLiteAutomationStore(root: root, key: key)
    let job = AutomationDefinition(id: "test", plugin: "dev.test@1.0.0")
    try await store.apply([job])
    let lease = try await store.claim(jobID: "test", occurrence: "one", now: .now)
    #expect(try await store.claim(jobID: "test", occurrence: "one", now: .now) == nil)
    try await store.complete(lease!, result: RunResult(events: [.init(sourceKey: "issue1", title: "secret title")], state: .object(["cursor": .number(1)])))
    let again = try SQLiteAutomationStore(root: root, key: key)
    #expect(try await again.inbox().count == 1)
    let second = try await again.claim(jobID: "test", occurrence: "two", now: .now)!
    try await again.complete(second, result: RunResult(events: [.init(sourceKey: "issue1", title: "Updated")]))
    #expect(try await again.inbox().count == 1)
    let raw = try Data(contentsOf: root.appendingPathComponent("automation.sqlite"))
    #expect(!String(decoding: raw, as: UTF8.self).contains("secret title"))
}

@Test func invalidResultCannotCommitState() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SQLiteAutomationStore(root: root, key: Data(repeating: 7, count: 32))
    try await store.apply([.init(id: "test", plugin: "dev.test@1.0.0")])
    let lease = try await store.claim(jobID: "test", occurrence: "one", now: .now)!
    await #expect(throws: (any Error).self) { try await store.complete(lease, result: RunResult(state: .string(String(repeating: "x", count: 70_000)))) }
    #expect(try await store.state(jobID: "test") == .empty)
}

@Test func configurationEditsPreserveNotificationRecordsAndInvalidateOldLease() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SQLiteAutomationStore(root: root, key: Data(repeating: 8, count: 32))
    var job = AutomationDefinition(id: "test", plugin: "dev.test@1.0.0")
    try await store.apply([job])
    let first = try await store.claim(jobID: "test", occurrence: "one", now: .now)!
    try await store.complete(first, result: RunResult(recordMutations: [.init(collection: "issues", key: "one", value: .object(["notified": .bool(true)]))]))
    let stale = try await store.claim(jobID: "test", occurrence: "two", now: .now)!
    job.config = .object(["minimumScore": .number(80)])
    try await store.apply([job])
    #expect(try await store.records(jobID: "test", collection: "issues").count == 1)
    await #expect(throws: (any Error).self) { try await store.complete(stale, result: RunResult(state: .object(["stale": .bool(true)]))) }
    #expect(try await store.state(jobID: "test") == .empty)
}

@Test func stopPreventsLateSuccessfulResultFromPublishing() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SQLiteAutomationStore(root: root, key: Data(repeating: 8, count: 32))
    try await store.apply([.init(id: "test", plugin: "dev.test@1.0.0")])
    let lease = try await store.claim(jobID: "test", occurrence: "one", now: .now)!
    try await store.setStopped(true)
    await #expect(throws: (any Error).self) { try await store.complete(lease, result: RunResult(events: [.init(sourceKey: "late", title: "Late")])) }
    #expect(try await store.inbox().isEmpty)
}
