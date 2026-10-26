import XCTest
import ShellFeature

final class ShellLatencyPerformanceTests: XCTestCase {
    func testGeometryResolutionStaysWithinWarmPathBudget() {
        let screen = ScreenDescriptor(
            id: "internal",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945),
            safeAreaInsets: EdgeInsets(top: 37, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 632, height: 37),
            auxiliaryTopRightArea: CGRect(x: 880, y: 945, width: 632, height: 37),
            isBuiltIn: true
        )
        let resolver = ShelfGeometryResolver()
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            _ = resolver.placement(screen: screen, contentSize: CGSize(width: 420, height: 88))
        }
    }
}
