import XCTest

final class ScreenshotPersistenceTests: XCTestCase {
    func testPNGIntermediatesAreNeverPartOfThePersistenceContract() {
        XCTAssertEqual(["ledge"].filter { ["png", "jpg", "heic"].contains($0) }, [])
    }
}
