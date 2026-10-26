import Foundation

public enum ExternalURLValidation: Sendable, Equatable {
    case success(URL)
    case failure(ExternalURLValidationError)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var isFailure: Bool { !isSuccess }
}

public enum ExternalURLValidationError: Error, Sendable, Equatable {
    case exceedsMaximumSize
    case containsControlCharacter
    case invalidPercentEncoding
    case malformedURL
    case unsupportedScheme
    case missingHost
    case credentialsNotAllowed
    case malformedHost
}

public struct ExternalURLPolicy: Sendable {
    public let maximumUTF8Bytes: Int

    public init(maximumUTF8Bytes: Int = 8_192) {
        self.maximumUTF8Bytes = max(0, maximumUTF8Bytes)
    }

    public func validate(_ value: String) -> ExternalURLValidation {
        guard value.lengthOfBytes(using: .utf8) <= maximumUTF8Bytes else { return .failure(.exceedsMaximumSize) }
        guard !value.unicodeScalars.contains(where: { $0.value <= 0x1F || $0.value == 0x7F }) else { return .failure(.containsControlCharacter) }
        guard Self.hasValidPercentEncoding(value) else { return .failure(.invalidPercentEncoding) }
        guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased(), components.url != nil else { return .failure(.malformedURL) }
        guard scheme == "http" || scheme == "https" else { return .failure(.unsupportedScheme) }
        guard components.user == nil, components.password == nil else { return .failure(.credentialsNotAllowed) }
        guard let host = components.host, !host.isEmpty else { return .failure(.missingHost) }
        guard Self.isUnambiguousHost(host) else { return .failure(.malformedHost) }
        guard let url = components.url, url.isFileURL == false else { return .failure(.malformedURL) }
        return .success(url)
    }

    private static func hasValidPercentEncoding(_ value: String) -> Bool {
        let characters = Array(value.utf8)
        for index in characters.indices where characters[index] == 37 {
            guard index + 2 < characters.count,
                  characters[index + 1].isASCIIHexDigit,
                  characters[index + 2].isASCIIHexDigit else { return false }
        }
        return true
    }

    private static func isUnambiguousHost(_ host: String) -> Bool {
        if host.contains(":") {
            return host.contains(":") && host.utf8.allSatisfy { $0.isASCIIHexDigit || $0 == 58 || $0 == 46 }
        }
        guard host.utf8.allSatisfy({ $0 < 128 }) else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, !labels.contains(where: { $0.isEmpty || $0.count > 63 }) else { return false }
        return labels.allSatisfy { label in
            let bytes = Array(label.utf8)
            guard let first = bytes.first, let last = bytes.last else { return false }
            return first != 45 && last != 45 && bytes.allSatisfy { $0.isASCIIAlphaNumeric || $0 == 45 }
        }
    }
}

private extension UInt8 {
    var isASCIIHexDigit: Bool { (48...57).contains(self) || (65...70).contains(self) || (97...102).contains(self) }
    var isASCIIAlphaNumeric: Bool { (48...57).contains(self) || (65...90).contains(self) || (97...122).contains(self) }
}
