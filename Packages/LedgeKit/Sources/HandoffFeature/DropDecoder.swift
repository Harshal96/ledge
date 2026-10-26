import Foundation
import LedgeDomain

public actor DropDecoder {
    public static let maximumItems = 100
    private let urlPolicy: ExternalURLPolicy
    public init(urlPolicy: ExternalURLPolicy = .init()) { self.urlPolicy = urlPolicy }
    public func decode(_ fileURL: URL) throws -> IncomingPayload {
        guard fileURL.isFileURL else { throw HandoffError.unsupportedInput }
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
        return .file(try FileDescriptorSource(url: fileURL))
    }
    public func decode(text: String) throws -> IncomingPayload {
        guard !text.isEmpty, text.lengthOfBytes(using: .utf8) <= 8_192 else { throw HandoffError.unsupportedInput }
        return .text(text)
    }
    public func decode(urlString: String) throws -> IncomingPayload {
        guard case let .success(url) = urlPolicy.validate(urlString) else { throw HandoffError.invalidURL }
        return .url(url)
    }
    public func decode(_ urls: [URL]) throws -> [IncomingPayload] {
        guard urls.count <= Self.maximumItems else { throw HandoffError.tooManyItems }
        return try urls.map { try decode($0) }
    }
}
