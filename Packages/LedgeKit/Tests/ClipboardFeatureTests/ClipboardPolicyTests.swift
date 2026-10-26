import XCTest
@testable import ClipboardFeature

final class ClipboardPolicyTests: XCTestCase {
    func testUnknownTransitionFailsClosed() {
        XCTAssertEqual(ClipboardPolicy(excludedBundleIDs: []).decision(previousBundleID: "com.example.Editor", currentBundleID: nil, declaredTypes: [.string]), .skip(.uncertainSource))
    }

    func testExcludedAndConcealedTypesAreSkippedBeforeReads() {
        let policy = ClipboardPolicy(excludedBundleIDs: ["com.example.Passwords"])
        XCTAssertEqual(policy.decision(previousBundleID: "com.example.Passwords", currentBundleID: "com.example.Passwords", declaredTypes: [.string]), .skip(.excludedApplication))
        XCTAssertEqual(policy.decision(previousBundleID: "com.example.Editor", currentBundleID: "com.example.Editor", declaredTypes: [.string, .transient]), .skip(.transientOrConcealed))
    }
}
