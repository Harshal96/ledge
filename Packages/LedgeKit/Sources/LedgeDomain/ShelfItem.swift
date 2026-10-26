import Foundation

public enum ShelfItemKind: String, Codable, Sendable, CaseIterable {
    case note, task, link, screenshot, clipboardText, clipboardURL
    case trayFile, trayText, trayURL
}

public struct SourceContext: Codable, Sendable, Equatable {
    public let bundleIdentifier: String?
    public let applicationName: String?
    public let explicitURL: URL?
    public let capturedAt: Date

    public init(bundleIdentifier: String?, applicationName: String?, explicitURL: URL? = nil, capturedAt: Date) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.explicitURL = explicitURL
        self.capturedAt = capturedAt
    }
}

public struct BinaryDescriptor: Sendable, Equatable {
    public let displayName: String
    public let byteCount: Int
    public let uniformTypeIdentifier: String?

    public init(displayName: String, byteCount: Int, uniformTypeIdentifier: String? = nil) {
        self.displayName = displayName
        self.byteCount = byteCount
        self.uniformTypeIdentifier = uniformTypeIdentifier
    }
}

public enum ShelfContent: Sendable, Equatable {
    case text(String)
    case url(URL)
    case task(title: String, isComplete: Bool)
    case binary(BinaryDescriptor)
}

public struct ShelfItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let kind: ShelfItemKind
    public let content: ShelfContent
    public let source: SourceContext?
    public let createdAt: Date
    public let expiresAt: Date?
    public let isFavorite: Bool

    public init(id: UUID, kind: ShelfItemKind, content: ShelfContent, source: SourceContext?, createdAt: Date, expiresAt: Date?, isFavorite: Bool = false) {
        self.id = id
        self.kind = kind
        self.content = content
        self.source = source
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.isFavorite = isFavorite
    }
}

public struct ShelfItemDraft: Sendable, Equatable {
    public let kind: ShelfItemKind
    public let content: ShelfContent
    public let source: SourceContext?
    public let createdAt: Date
    public let expiresAt: Date?

    public init(kind: ShelfItemKind, content: ShelfContent, source: SourceContext?, createdAt: Date, expiresAt: Date?) {
        self.kind = kind
        self.content = content
        self.source = source
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public static func note(_ text: String, now: Date = .now) -> Self {
        Self(kind: .note, content: .text(text), source: nil, createdAt: now, expiresAt: now.addingTimeInterval(30 * 86_400))
    }
}
