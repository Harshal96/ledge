import XCTest
@testable import ClipboardFeature

final class ClipboardSearchTests: XCTestCase {
    func testCaseAndDiacriticInsensitiveSearchFavorsFavorites() async {
        let search = ClipboardSearch()
        await search.replace(with: [ClipboardSnapshot(id: UUID(), value: .text("Résumé"), createdAt: .now, isFavorite: false, usageCount: 0), ClipboardSnapshot(id: UUID(), value: .text("resume runbook"), createdAt: .distantPast, isFavorite: true, usageCount: 0)])
        let results = await search.results(matching: "resume")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.first?.isFavorite == true)
    }
}
