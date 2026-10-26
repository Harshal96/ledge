import CoreImage
import Foundation
import LedgeDomain

public enum QRCodeError: Error, Sendable, Equatable { case filesUnsupported, invalidURL, payloadTooLarge, confirmationExpired, presentationSafeRevealRequired, generationFailed }

public struct QRCodeDisclosure: Sendable, Equatable {
    public let payload: Data
    public let exactValue: String
    public let warning: String
    public let expiresAt: Date
}

public struct QRCodeService: Sendable {
    public let maxUTF8Bytes: Int
    public let timeout: TimeInterval
    private let urlPolicy: ExternalURLPolicy

    public init(maxUTF8Bytes: Int = 2_048, timeout: TimeInterval = 60, urlPolicy: ExternalURLPolicy = .init()) {
        self.maxUTF8Bytes = max(0, maxUTF8Bytes); self.timeout = max(0, timeout); self.urlPolicy = urlPolicy
    }

    public func payload(for value: SharePayload) throws -> Data {
        let string: String
        switch value {
        case let .text(text): string = text
        case let .url(url):
            guard case let .success(validated) = urlPolicy.validate(url.absoluteString) else { throw QRCodeError.invalidURL }
            string = validated.absoluteString
        case .file: throw QRCodeError.filesUnsupported
        }
        let data = Data(string.utf8)
        guard data.count <= maxUTF8Bytes else { throw QRCodeError.payloadTooLarge }
        return data
    }

    public func disclosure(for value: SharePayload, now: Date = .now, presentationSafeRevealed: Bool = true) throws -> QRCodeDisclosure {
        guard presentationSafeRevealed else { throw QRCodeError.presentationSafeRevealRequired }
        let data = try payload(for: value)
        return .init(payload: data, exactValue: String(decoding: data, as: UTF8.self), warning: "Anyone who can see or scan this code can read this payload.", expiresAt: now.addingTimeInterval(timeout))
    }

    public func confirm(_ disclosure: QRCodeDisclosure, now: Date = .now) throws -> Data {
        guard now < disclosure.expiresAt else { throw QRCodeError.confirmationExpired }
        return disclosure.payload
    }

    /// Returns an in-memory Core Image QR code (M correction); callers must not persist it.
    public func image(for confirmedPayload: Data) throws -> CIImage {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw QRCodeError.generationFailed }
        filter.setValue(confirmedPayload, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage else { throw QRCodeError.generationFailed }
        return image.transformed(by: .init(scaleX: 8, y: 8))
    }
}
