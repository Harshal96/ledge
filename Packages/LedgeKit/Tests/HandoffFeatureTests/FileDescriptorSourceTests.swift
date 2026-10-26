import Foundation
import Testing
@testable import HandoffFeature

@Test("Descriptor source reads the originally opened regular file")
func descriptorSourceReadsRegularFile() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "ledge-descriptor-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: file) }
    let bytes = Data("safe bytes".utf8)
    try bytes.write(to: file)
    let source = try FileDescriptorSource(url: file)
    defer { source.close() }
    #expect(try source.readData() == bytes)
    #expect(source.descriptor.displayName == file.lastPathComponent)
}
