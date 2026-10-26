import Foundation
import Testing
@testable import HandoffFeature

@Test("Drop decoder accepts regular files and rejects unsafe filesystem objects")
func dropDecoderRejectsUnsafeObjects() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "ledge-drop-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "report.pdf")
    try Data([1, 2, 3]).write(to: file)
    let directory = root.appending(path: "folder")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let link = root.appending(path: "link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    let decoder = DropDecoder()

    #expect(try await decoder.decode(file).isAccepted)
    await #expect(throws: HandoffError.directoryUnsupported) { try await decoder.decode(directory) }
    await #expect(throws: HandoffError.symbolicLinkUnsupported) { try await decoder.decode(link) }
}

@Test("Drop decoder validates URL input and sanitizes file names")
func dropDecoderValidatesURLAndName() async throws {
    let decoder = DropDecoder()
    #expect(try await decoder.decode(text: "hello").isAccepted)
    #expect(try await decoder.decode(urlString: "https://example.com/handoff").isAccepted)
    await #expect(throws: HandoffError.invalidURL) { try await decoder.decode(urlString: "file:///secret") }
    #expect(FileDescriptorSource.sanitizedDisplayName("../../bad\u{0}name") == "badname")
}
