import XCTest
import LedgeDomain
@testable import HandoffFeature

final class HandoffFileTransactionTests: XCTestCase {
    func testDirectoryDropDoesNotCreateAnItem() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ledge-handoff-directory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let decoder = DropDecoder()
        do { _ = try await decoder.decode(root); XCTFail("directory was accepted") }
        catch HandoffError.directoryUnsupported { }
    }
}
