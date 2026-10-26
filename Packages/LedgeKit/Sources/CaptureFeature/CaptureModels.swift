import Foundation
import LedgeDomain

public enum CaptureType: String, Sendable, CaseIterable, Identifiable {
    case note, task, link, screenshot
    public var id: String { rawValue }
    public var shelfKind: ShelfItemKind { switch self { case .note: .note; case .task: .task; case .link: .link; case .screenshot: .screenshot } }
}

public enum CaptureValidationError: Error, Sendable, Equatable {
    case emptyContent
    case contentExceedsMaximumSize
    case unsupportedURLScheme
    case invalidURL
}

public struct CaptureContextURL: Sendable, Equatable {
    public let value: URL
    public init(_ value: URL) { self.value = value }

    public static func parse(_ rawValue: String, policy: ExternalURLPolicy = .init()) -> Result<CaptureContextURL, CaptureValidationError> {
        switch policy.validate(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case .success(let url): .success(CaptureContextURL(url))
        case .failure(.unsupportedScheme): .failure(.unsupportedURLScheme)
        case .failure: .failure(.invalidURL)
        }
    }
}

public struct CaptureDraft: Sendable, Equatable {
    public static let maximumContentUTF8Bytes = 64 * 1024
    public let type: CaptureType
    public let text: String
    public let source: SourceContext?
    /// `false` records a privacy action such as Remove all context, so save must not restore the frozen app snapshot.
    public let allowsFrozenSourceAttachment: Bool

    public init(type: CaptureType, text: String, source: SourceContext? = nil, allowsFrozenSourceAttachment: Bool = true) {
        self.type = type
        self.text = text
        self.source = source
        self.allowsFrozenSourceAttachment = allowsFrozenSourceAttachment
    }

    public static func parse(_ rawValue: String, explicitType: CaptureType? = nil, source: SourceContext? = nil, urlPolicy: ExternalURLPolicy = .init()) -> Result<CaptureDraft, CaptureValidationError> {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = explicitType ?? prefix(in: raw).type
        let content = (explicitType == nil ? prefix(in: raw).content : raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return .failure(.emptyContent) }
        guard content.lengthOfBytes(using: .utf8) <= maximumContentUTF8Bytes else { return .failure(.contentExceedsMaximumSize) }
        if resolved == .link {
            switch urlPolicy.validate(content) {
            case .success: break
            case .failure(.unsupportedScheme): return .failure(.unsupportedURLScheme)
            case .failure: return .failure(.invalidURL)
            }
        }
        return .success(CaptureDraft(type: resolved, text: content, source: source))
    }

    public func withContextURL(_ context: CaptureContextURL?) -> CaptureDraft {
        guard let context else { return CaptureDraft(type: type, text: text, source: source.map { SourceContext(bundleIdentifier: $0.bundleIdentifier, applicationName: $0.applicationName, capturedAt: $0.capturedAt) }, allowsFrozenSourceAttachment: allowsFrozenSourceAttachment) }
        let base = source ?? SourceContext(bundleIdentifier: nil, applicationName: nil, capturedAt: .now)
        return CaptureDraft(type: type, text: text, source: SourceContext(bundleIdentifier: base.bundleIdentifier, applicationName: base.applicationName, explicitURL: context.value, capturedAt: base.capturedAt), allowsFrozenSourceAttachment: false)
    }

    public func removingApplicationContext() -> CaptureDraft {
        guard let source else { return self }
        let retained = source.explicitURL.map { SourceContext(bundleIdentifier: nil, applicationName: nil, explicitURL: $0, capturedAt: source.capturedAt) }
        return CaptureDraft(type: type, text: text, source: retained, allowsFrozenSourceAttachment: false)
    }

    public func removingAllContext() -> CaptureDraft { CaptureDraft(type: type, text: text, allowsFrozenSourceAttachment: false) }

    public func shelfItemDraft(now: Date) throws -> ShelfItemDraft {
        let content: ShelfContent
        switch type {
        case .note: content = .text(text)
        case .task: content = .task(title: text, isComplete: false)
        case .link:
            guard case .success(let url) = ExternalURLPolicy().validate(text) else { throw CaptureValidationError.invalidURL }
            content = .url(url)
        case .screenshot: content = .text(text)
        }
        return ShelfItemDraft(kind: type.shelfKind, content: content, source: source, createdAt: now, expiresAt: now.addingTimeInterval(30 * 86_400))
    }

    private static func prefix(in value: String) -> (type: CaptureType, content: String) {
        guard value.count >= 2, value[value.index(after: value.startIndex)] == " " else { return (.note, value) }
        switch value.first {
        case "n": return (.note, String(value.dropFirst(2)))
        case "t": return (.task, String(value.dropFirst(2)))
        case "l": return (.link, String(value.dropFirst(2)))
        default: return (.note, value)
        }
    }
}

public enum QuickCaptureActions {
    public static let candidates: [ActionCandidate] = [ActionCandidate(id: FixedActionID.quickCapture, feature: .quickCapture, title: "Quick Capture", urgency: .available, sensitivity: .public, command: .openQuickCapture)]
}
