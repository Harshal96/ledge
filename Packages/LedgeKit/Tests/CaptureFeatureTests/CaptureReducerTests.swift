import XCTest
@testable import CaptureFeature
import LedgeDomain

final class CaptureReducerTests: XCTestCase {
    func testParsesTypesAndTrimsContent() throws {
        XCTAssertEqual(try CaptureDraft.parse(" n  hello  ").get().type, .note)
        XCTAssertEqual(try CaptureDraft.parse("t  complete this ").get().type, .task)
        XCTAssertEqual(try CaptureDraft.parse("l https://example.com/runbook ").get().type, .link)
    }

    func testRejectsUnsafeAndEmptyContent() {
        XCTAssertEqual(CaptureDraft.parse("l javascript:alert(1)"), .failure(.unsupportedURLScheme))
        XCTAssertEqual(CaptureDraft.parse("  "), .failure(.emptyContent))
        XCTAssertEqual(CaptureContextURL.parse("data:text/plain,secret"), .failure(.unsupportedURLScheme))
    }

    @MainActor func testContextRemovalAndSaveCancelReducer() throws {
        let source = SourceContext(bundleIdentifier: "com.example.Editor", applicationName: "Editor", explicitURL: URL(string: "https://example.com/runbook"), capturedAt: .distantPast)
        let state = CaptureStore.State.initial(source: source)
        XCTAssertNil(CaptureStore.reduce(state, .removeAllContext).draft.source)
        XCTAssertEqual(CaptureStore.reduce(state, .cancel).presentation, .dismissed)
    }

    func testContentCapIs64KiB() {
        XCTAssertEqual(CaptureDraft.parse("n " + String(repeating: "a", count: 65_537)), .failure(.contentExceedsMaximumSize))
    }

    func testDraftsBecomeExpectedShelfContent() throws {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(try CaptureDraft.parse("n note").get().shelfItemDraft(now: now).content, .text("note"))
        XCTAssertEqual(try CaptureDraft.parse("t task").get().shelfItemDraft(now: now).content, .task(title: "task", isComplete: false))
        XCTAssertEqual(try CaptureDraft.parse("l https://example.com/runbook").get().shelfItemDraft(now: now).content, .url(URL(string: "https://example.com/runbook")!))
    }
}
