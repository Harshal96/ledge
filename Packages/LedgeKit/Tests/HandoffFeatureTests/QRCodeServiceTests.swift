import Foundation
import Testing
@testable import HandoffFeature

@Test("QR accepts bounded text and HTTPS URLs but rejects files and invalid URLs")
func qrPolicy() throws {
    let service = QRCodeService(maxUTF8Bytes: 2_048)
    #expect(try service.payload(for: .text("pair this device")) == Data("pair this device".utf8))
    #expect(try service.payload(for: .url(URL(string: "https://example.com/pair")!)).count > 0)
    #expect(throws: QRCodeError.filesUnsupported) { try service.payload(for: .file(.init(itemID: UUID(), descriptor: .init(displayName: "private.pdf", byteCount: 3)))) }
    #expect(throws: QRCodeError.invalidURL) { try service.payload(for: .url(URL(string: "file:///private/secret")!)) }
}

@Test("QR rejects payloads over its byte limit")
func qrRejectsOversizedPayload() {
    let service = QRCodeService(maxUTF8Bytes: 2)
    #expect(throws: QRCodeError.payloadTooLarge) { try service.payload(for: .text("abc")) }
}

@Test("QR disclosure is explicit and expires after sixty seconds")
func qrDisclosureExpiry() throws {
    let service = QRCodeService()
    let now = Date(timeIntervalSince1970: 1_000)
    let disclosure = try service.disclosure(for: .text("visible"), now: now)
    #expect(disclosure.warning == "Anyone who can see or scan this code can read this payload.")
    #expect(throws: QRCodeError.confirmationExpired) { try service.confirm(disclosure, now: now.addingTimeInterval(60)) }
    #expect(try service.confirm(disclosure, now: now.addingTimeInterval(59)) == Data("visible".utf8))
}
