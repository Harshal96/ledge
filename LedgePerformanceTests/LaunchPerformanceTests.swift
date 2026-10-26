import XCTest

final class LaunchPerformanceTests: XCTestCase {
    func testPerformanceFixtureDocumentsColdLaunchBudget() {
        // The real signed-app launch is measured by measure-idle-energy.sh and
        // the Xcode app test target. Keep this fixture free of private APIs.
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            _ = ProcessInfo.processInfo.operatingSystemVersion
        }
    }
}
