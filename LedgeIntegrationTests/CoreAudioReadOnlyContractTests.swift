import XCTest

final class CoreAudioReadOnlyContractTests: XCTestCase {
    func testReadOnlyContractFixtureDoesNotWriteHardware() {
        // CI must never change the machine's default route, volume, or mute
        // state. Opt-in hardware writes are intentionally a local-only suite.
        XCTAssertNil(ProcessInfo.processInfo.environment["LEDGE_AUDIO_WRITE_TESTS"])
    }
}
