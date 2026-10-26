import CoreGraphics
import XCTest
@testable import CaptureFeature

final class RegionSelectionTests: XCTestCase {
    private let secondary = ScreenshotDisplay(id: "secondary", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), backingScale: 2)

    func testEscapeCancelsSelection() {
        XCTAssertEqual(RegionSelectionReducer.reduce(.selecting(screenID: "secondary", rect: CGRect(x: -100, y: 20, width: 30, height: 20)), .escape, display: secondary), .canceled)
    }

    func testArrowsMoveOnePointAndShiftMovesTenPoints() {
        let state = RegionSelectionState.selecting(screenID: "secondary", rect: CGRect(x: -100, y: 20, width: 30, height: 20))
        XCTAssertEqual(RegionSelectionReducer.reduce(state, .arrow(.left, shift: false), display: secondary), .selecting(screenID: "secondary", rect: CGRect(x: -101, y: 20, width: 30, height: 20)))
        XCTAssertEqual(RegionSelectionReducer.reduce(state, .arrow(.down, shift: true), display: secondary), .selecting(screenID: "secondary", rect: CGRect(x: -100, y: 10, width: 30, height: 20)))
    }

    func testReturnRejectsARegionCrossingDisplayBoundary() {
        let state = RegionSelectionState.selecting(screenID: "secondary", rect: CGRect(x: -10, y: 20, width: 20, height: 20))
        XCTAssertEqual(RegionSelectionReducer.reduce(state, .returnKey, display: secondary), .rejected("Select an area within one display."))
    }
}
