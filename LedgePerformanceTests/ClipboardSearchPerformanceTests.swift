import ClipboardFeature
import XCTest

final class ClipboardSearchPerformanceTests: XCTestCase {
    func testSearchAcrossCappedCache() async {
        let search = ClipboardSearch(capacity: 500)
        let entries = (0..<750).map { index in
            ClipboardSnapshot(id: UUID(), value: .text("snippet \(index)"), createdAt: Date(timeIntervalSince1970: TimeInterval(index)), isFavorite: index % 17 == 0, usageCount: index % 5)
        }
        await search.replace(with: entries)
        measure {
            let expectation = expectation(description: "search")
            Task {
                _ = await search.results(matching: "snippet 42")
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1)
        }
        let count = await search.results(matching: "").count
        XCTAssertEqual(count, 500)
    }
}
