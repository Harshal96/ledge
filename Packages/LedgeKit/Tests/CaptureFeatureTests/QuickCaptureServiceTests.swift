import XCTest
@testable import CaptureFeature
import LedgeDomain
import ShellFeature

@MainActor
final class QuickCaptureServiceTests: XCTestCase {
    func testSourceSnapshotPrecedesReveal() async throws {
        let events = EventLog()
        let source = RecordingSourceProvider(events: events)
        let panel = RecordingPanel(events: events)
        let repository = MemoryRepository()
        let service = QuickCaptureService(source: source, panel: panel, repository: repository)

        try await service.beginCapture(at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(events.events, ["source", "reveal"])
    }

    func testSourceFreeCaptureSkipsProvider() async throws {
        let source = RecordingSourceProvider(events: EventLog())
        let service = QuickCaptureService(source: source, sourcePolicy: .neverAttach, panel: RecordingPanel(events: EventLog()), repository: MemoryRepository())

        try await service.beginCapture(at: .distantPast)

        XCTAssertEqual(source.readCount, 0)
    }

    func testSaveUsesFrozenSourceAndNeverRequeries() async throws {
        let source = RecordingSourceProvider(events: EventLog())
        let repository = MemoryRepository()
        let service = QuickCaptureService(source: source, panel: RecordingPanel(events: EventLog()), repository: repository)
        try await service.beginCapture(at: .distantPast)
        let draft = try XCTUnwrap(CaptureDraft.parse("n Ship the smallest useful slice").get())

        _ = try await service.save(draft)

        XCTAssertEqual(source.readCount, 1)
        let persisted = await repository.firstDraft()
        XCTAssertEqual(persisted?.source?.applicationName, "Editor")
    }

    func testRemoveAllContextDoesNotReattachFrozenSource() async throws {
        let source = RecordingSourceProvider(events: EventLog())
        let repository = MemoryRepository()
        let service = QuickCaptureService(source: source, panel: RecordingPanel(events: EventLog()), repository: repository)
        try await service.beginCapture(at: .distantPast)
        let draft = try XCTUnwrap(CaptureDraft.parse("n private note").get()).removingAllContext()

        _ = try await service.save(draft)

        let persisted = await repository.firstDraft()
        XCTAssertNil(persisted?.source)
        XCTAssertEqual(source.readCount, 1)
    }
}

private final class EventLog { var events: [String] = [] }

@MainActor
private final class RecordingSourceProvider: SourceContextProviding {
    let events: EventLog
    private(set) var readCount = 0
    init(events: EventLog) { self.events = events }
    func snapshot(at date: Date) async -> SourceContext? {
        readCount += 1
        events.events.append("source")
        return SourceContext(bundleIdentifier: "com.example.Editor", applicationName: "Editor", capturedAt: date)
    }
}

@MainActor
private final class RecordingPanel: ShellPanelControlling {
    let events: EventLog
    init(events: EventLog) { self.events = events }
    func reveal(_ route: ShelfRoute, reason: RevealReason, screenID: String?) { events.events.append("reveal") }
    func dismiss(reason: DismissReason) { events.events.append("dismiss") }
    func beginExternalInteraction(_ kind: ExternalInteractionKind) -> ExternalInteractionToken { ExternalInteractionToken(kind: kind) }
    func endExternalInteraction(_ token: ExternalInteractionToken) {}
    func resetPosition() {}
}

private actor MemoryRepository: ShelfRepository {
    private(set) var inserted: [ShelfItemDraft] = []
    func firstDraft() -> ShelfItemDraft? { inserted.first }
    func insert(_ draft: ShelfItemDraft) async throws -> ShelfItem { inserted.append(draft); return ShelfItem(id: UUID(), kind: draft.kind, content: draft.content, source: draft.source, createdAt: draft.createdAt, expiresAt: draft.expiresAt) }
    nonisolated func importFile(_ request: FileImportRequest) -> AsyncThrowingStream<ImportProgress, Error> { .init { $0.finish() } }
    func item(id: UUID) async throws -> ShelfItem? { nil }
    func list(_ query: ShelfQuery) async throws -> [ShelfItem] { [] }
    func setFavorite(id: UUID, isFavorite: Bool) async throws -> ShelfItem { throw TestError.unimplemented }
    func setTaskComplete(id: UUID, isComplete: Bool) async throws -> ShelfItem { throw TestError.unimplemented }
    func export(id: UUID, to destination: URL) async throws -> ExportReceipt { throw TestError.unimplemented }
    func delete(id: UUID) async throws {}
    func purgeExpired(before date: Date) async throws -> PurgeReport { .init() }
}
private enum TestError: Error { case unimplemented }
