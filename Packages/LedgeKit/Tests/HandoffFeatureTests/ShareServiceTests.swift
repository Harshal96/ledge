import Foundation
import Testing
import LedgeDomain
@testable import HandoffFeature

@Test("Share cleans an exported file after completion, cancellation, and failure")
func shareCleansTemporaryExport() async throws {
    for result in [SharingResult.completed, .cancelled, .failed("sharing failed")] {
        let exporter = RecordingTemporaryExporter()
        let client = RecordingSharingClient(result: result)
        let service = ShareService(exporter: exporter, sharingClient: client)
        let payload = SharePayload.file(.init(itemID: UUID(), descriptor: .init(displayName: "report.pdf", byteCount: 3)))
        if result == .completed { try await service.share(payload) }
        else { await #expect(throws: ShareError.self) { try await service.share(payload) } }
        #expect(await exporter.removed == true)
    }
}

@Test("Share reports unavailable services and does not export a file")
func unavailableShareDoesNotExport() async {
    let exporter = RecordingTemporaryExporter()
    let service = ShareService(exporter: exporter, sharingClient: RecordingSharingClient(available: false, result: .completed))
    await #expect(throws: ShareError.unavailable) { try await service.share(.text("hello"), mode: .airDrop) }
    #expect(await exporter.exported == false)
}

@Test("Share uses an interaction lease for every terminal result")
func shareReleasesLease() async throws {
    let lease = RecordingLease()
    let service = ShareService(exporter: RecordingTemporaryExporter(), sharingClient: RecordingSharingClient(result: .completed), interactionLease: lease)
    try await service.share(.url(URL(string: "https://example.com")!))
    #expect(await lease.acquired == 1)
    #expect(await lease.released == 1)
}

private actor RecordingTemporaryExporter: TemporaryShareExporting {
    var exported = false
    var removed = false
    func exportTemporary(itemID: UUID, suggestedName: String) async throws -> URL { exported = true; return URL(fileURLWithPath: "/tmp/\(suggestedName)") }
    func removeTemporary(_ url: URL) async { removed = true }
}

private actor RecordingSharingClient: SharingClient {
    let available: Bool
    let result: SharingResult
    init(available: Bool = true, result: SharingResult) { self.available = available; self.result = result }
    func isAvailable(for mode: ShareMode) async -> Bool { available }
    func share(_ items: [ShareItem], mode: ShareMode) async -> SharingResult { result }
}

private actor RecordingLease: ExternalInteractionLeasing {
    var acquired = 0
    var released = 0
    func acquire(kind: ExternalInteractionKind) async -> UUID { acquired += 1; return UUID() }
    func release(_ token: UUID) async { released += 1 }
}
