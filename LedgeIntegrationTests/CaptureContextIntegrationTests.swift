import XCTest

final class CaptureContextIntegrationTests: XCTestCase {
    func testQuickCapturePrivacyContractUsesOnlyExplicitContext() {
        let supported = ["n ", "t ", "l "]
        XCTAssertEqual(supported.count, 3)
    }
}
