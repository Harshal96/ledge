import XCTest
@testable import ClipboardFeature
import LedgeDomain

final class ClipboardMonitorTests: XCTestCase {
    func testExcludedAppAdvancesWatermarkWithoutReadingContent() async throws {
        let pasteboard = FakePasteboard(changeCount: 12, text: "never persist me")
        let monitor = ClipboardMonitor(pasteboard: pasteboard, activeApps: FakeActiveApps(previous: "com.example.Passwords", current: "com.example.Passwords"), policy: ClipboardPolicy(excludedBundleIDs: ["com.example.Passwords"]), repository: MemoryRepository())
        await monitor.setOptedIn(true)
        await monitor.pollOnce()
        let reads = await pasteboard.contentReadCount
        let typeReads = await pasteboard.typeReadCount
        let watermark = await monitor.watermark
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(typeReads, 0)
        XCTAssertEqual(watermark, 12)
    }

    func testUncertainSourceDoesNotReadTypesOrContent() async {
        let pasteboard = FakePasteboard(changeCount: 7, text: "never inspect me")
        let monitor = ClipboardMonitor(pasteboard: pasteboard, activeApps: FakeActiveApps(previous: "com.example.Editor", current: nil), policy: ClipboardPolicy(excludedBundleIDs: []), repository: MemoryRepository())
        await monitor.setOptedIn(true)
        await monitor.pollOnce()
        let typeReads = await pasteboard.typeReadCount
        let contentReads = await pasteboard.contentReadCount
        XCTAssertEqual(typeReads, 0)
        XCTAssertEqual(contentReads, 0)
    }

    func testSelfWriteAndOversizedContentAreNotPersisted() async throws {
        let pasteboard = FakePasteboard(changeCount: 1, text: String(repeating: "x", count: 65 * 1024))
        let repository = MemoryRepository()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, activeApps: FakeActiveApps(previous: "com.example.Editor", current: "com.example.Editor"), policy: ClipboardPolicy(excludedBundleIDs: []), repository: repository)
        await monitor.setOptedIn(true)
        await monitor.pollOnce()
        let count = await repository.count
        XCTAssertEqual(count, 0)
    }
}

private actor FakePasteboard: PasteboardClient {
    let changeCount: Int; let text: String; var contentReadCount = 0; var typeReadCount = 0
    init(changeCount: Int, text: String) { self.changeCount = changeCount; self.text = text }
    var accessState: PasteboardAccessState { .legacyUnavailable }
    var declaredTypes: Set<PasteboardType> { typeReadCount += 1; return [.string] }
    func readText(maximumUTF8Bytes: Int) async -> String? { contentReadCount += 1; return text }
    func readURL() async -> URL? { nil }
    func write(_ value: ClipboardValue) async -> Int { changeCount }
    func userInitiatedAccessProbe() async -> PasteboardAccessState { .legacyUnavailable }
}
private struct FakeActiveApps: ActiveApplicationProviding, Sendable { let previous: String?; let current: String?; func activationBundleIDs() async -> (previous: String?, current: String?) { (previous, current) } }
private actor MemoryRepository: ShelfRepository {
    var count = 0
    func insert(_ draft: ShelfItemDraft) async throws -> ShelfItem { count += 1; return ShelfItem(id: UUID(), kind: draft.kind, content: draft.content, source: draft.source, createdAt: draft.createdAt, expiresAt: draft.expiresAt) }
    nonisolated func importFile(_ request: FileImportRequest) -> AsyncThrowingStream<ImportProgress, Error> { .init { $0.finish() } }
    func item(id: UUID) async throws -> ShelfItem? { nil }; func list(_ query: ShelfQuery) async throws -> [ShelfItem] { [] }; func setFavorite(id: UUID, isFavorite: Bool) async throws -> ShelfItem { fatalError() }; func setTaskComplete(id: UUID, isComplete: Bool) async throws -> ShelfItem { fatalError() }; func export(id: UUID, to destination: URL) async throws -> ExportReceipt { fatalError() }; func delete(id: UUID) async throws {}; func purgeExpired(before date: Date) async throws -> PurgeReport { .init() }
}
