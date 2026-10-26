import CoreGraphics
import XCTest
@testable import CaptureFeature
import LedgeDomain
import ShellFeature

@MainActor
final class ScreenshotServiceTests: XCTestCase {
    func testDeniedPermissionCreatesNoItemAndDoesNotCallBackend() async {
        let repository = ScreenshotMemoryRepository()
        let backend = ScreenshotBackendSpy()
        let service = ScreenshotService(permission: FixedPermission(.denied), backend: backend, repository: repository, displays: [])

        await XCTAssertThrowsErrorAsync(try await service.capture(.region(CGRect(x: 10, y: 20, width: 30, height: 20)))) { XCTAssertEqual($0 as? ScreenshotError, .permissionDenied) }

        let itemCount = await repository.count
        let backendCalls = await backend.calls
        XCTAssertEqual(itemCount, 0)
        XCTAssertEqual(backendCalls, 0)
    }

    func testSnapshotOccursBeforeShellHideAndSourceFreeDoesNotQuery() async throws {
        let events = ScreenshotEventLog()
        let repository = ScreenshotMemoryRepository()
        let source = ScreenshotSource(events: events)
        let panel = ScreenshotPanel(events: events)
        let service = ScreenshotService(permission: FixedPermission(.authorized), backend: ScreenshotBackendSpy(), repository: repository, source: source, sourcePolicy: .attachApplication, panel: panel, displays: [.init(id: "main", frame: CGRect(x: 0, y: 0, width: 100, height: 100), backingScale: 1)])

        _ = try await service.capture(.region(CGRect(x: 10, y: 20, width: 30, height: 20)), now: .distantPast)

        XCTAssertEqual(Array(events.events.prefix(2)), ["source", "dismiss"])
        let sourceFree = ScreenshotSource(events: ScreenshotEventLog())
        let sourceFreeService = ScreenshotService(permission: FixedPermission(.authorized), backend: ScreenshotBackendSpy(), repository: ScreenshotMemoryRepository(), source: sourceFree, sourcePolicy: .neverAttach, displays: [.init(id: "main", frame: CGRect(x: 0, y: 0, width: 100, height: 100), backingScale: 1)])
        _ = try await sourceFreeService.capture(.region(CGRect(x: 10, y: 20, width: 30, height: 20)))
        XCTAssertEqual(sourceFree.count, 0)
    }

    func testWritesPNGBytesDirectlyAsScreenshotItem() async throws {
        let repository = ScreenshotMemoryRepository()
        let service = ScreenshotService(permission: FixedPermission(.authorized), backend: ScreenshotBackendSpy(), repository: repository, displays: [.init(id: "retina", frame: CGRect(x: -100, y: 0, width: 100, height: 100), backingScale: 2)])

        _ = try await service.capture(.region(CGRect(x: -80, y: 20, width: 20, height: 10)), now: .distantPast)

        let write = await repository.binaryWrite
        XCTAssertEqual(write?.draft.kind, .screenshot)
        XCTAssertEqual(write.map { Data($0.bytes.prefix(8)) }, Data([137, 80, 78, 71, 13, 10, 26, 10]))
        XCTAssertEqual(write?.draft.source?.applicationName, nil)
    }

    func testCaptureFailureLeavesNoItem() async {
        let repository = ScreenshotMemoryRepository()
        let service = ScreenshotService(permission: FixedPermission(.authorized), backend: ThrowingScreenshotBackend(), repository: repository, displays: [.init(id: "main", frame: CGRect(x: 0, y: 0, width: 100, height: 100), backingScale: 1)])

        await XCTAssertThrowsErrorAsync(try await service.capture(.region(CGRect(x: 10, y: 20, width: 30, height: 20)))) { XCTAssertEqual($0 as? ScreenshotError, .captureFailed) }

        let itemCount = await repository.count
        XCTAssertEqual(itemCount, 0)
    }
}

private struct FixedPermission: ScreenCapturePermissionChecking { let value: ScreenCapturePermission; init(_ value: ScreenCapturePermission) { self.value = value }; func authorization() async -> ScreenCapturePermission { value }; func requestAccess() async -> ScreenCapturePermission { value } }
private actor ScreenshotBackendSpy: ScreenshotFrameCapturing { private(set) var calls = 0; func capture(display: ScreenshotDisplay, excludingBundleIdentifier: String?) async throws -> ScreenshotFrame { calls += 1; return .fixture(width: Int(display.frame.width * display.backingScale), height: Int(display.frame.height * display.backingScale)) } }
private struct ThrowingScreenshotBackend: ScreenshotFrameCapturing { func capture(display: ScreenshotDisplay, excludingBundleIdentifier: String?) async throws -> ScreenshotFrame { throw ScreenshotError.captureFailed } }
private final class ScreenshotEventLog { var events: [String] = [] }
@MainActor private final class ScreenshotSource: SourceContextProviding { let events: ScreenshotEventLog; private(set) var count = 0; init(events: ScreenshotEventLog) { self.events = events }; func snapshot(at date: Date) async -> SourceContext? { count += 1; events.events.append("source"); return SourceContext(bundleIdentifier: "com.example.Editor", applicationName: "Editor", capturedAt: date) } }
@MainActor private final class ScreenshotPanel: ShellPanelControlling { let events: ScreenshotEventLog; init(events: ScreenshotEventLog) { self.events = events }; func reveal(_ route: ShelfRoute, reason: RevealReason, screenID: String?) { events.events.append("reveal") }; func dismiss(reason: DismissReason) { events.events.append("dismiss") }; func beginExternalInteraction(_ kind: ExternalInteractionKind) -> ExternalInteractionToken { .init(kind: kind) }; func endExternalInteraction(_ token: ExternalInteractionToken) {}; func resetPosition() {} }
private actor ScreenshotMemoryRepository: ShelfRepository { struct BinaryWrite: Sendable { let draft: ShelfItemDraft; let bytes: Data }; private(set) var binaryWrite: BinaryWrite?; var count: Int { binaryWrite == nil ? 0 : 1 }; func insert(_ draft: ShelfItemDraft) async throws -> ShelfItem { makeItem(draft) }; func insertBinary(_ draft: ShelfItemDraft, bytes: Data) async throws -> ShelfItem { binaryWrite = .init(draft: draft, bytes: bytes); return makeItem(draft) }; nonisolated func importFile(_ request: FileImportRequest) -> AsyncThrowingStream<ImportProgress, Error> { .init { $0.finish() } }; func item(id: UUID) async throws -> ShelfItem? { nil }; func list(_ query: ShelfQuery) async throws -> [ShelfItem] { [] }; func setFavorite(id: UUID, isFavorite: Bool) async throws -> ShelfItem { throw ScreenshotTestError.unimplemented }; func setTaskComplete(id: UUID, isComplete: Bool) async throws -> ShelfItem { throw ScreenshotTestError.unimplemented }; func export(id: UUID, to destination: URL) async throws -> ExportReceipt { throw ScreenshotTestError.unimplemented }; func delete(id: UUID) async throws {}; func purgeExpired(before date: Date) async throws -> PurgeReport { .init() }; private func makeItem(_ draft: ShelfItemDraft) -> ShelfItem { .init(id: UUID(), kind: draft.kind, content: draft.content, source: draft.source, createdAt: draft.createdAt, expiresAt: draft.expiresAt) } }
private enum ScreenshotTestError: Error { case unimplemented }
@MainActor private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, _ handler: (Error) -> Void) async { do { _ = try await expression(); XCTFail("Expected error") } catch { handler(error) } }
