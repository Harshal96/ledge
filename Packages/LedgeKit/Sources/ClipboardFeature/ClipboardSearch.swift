import Foundation

public struct ClipboardSnapshot: Identifiable, Sendable, Hashable {
    public let id: UUID; public let value: ClipboardValue; public let createdAt: Date; public let isFavorite: Bool; public let usageCount: Int
    public init(id: UUID, value: ClipboardValue, createdAt: Date, isFavorite: Bool, usageCount: Int) { self.id = id; self.value = value; self.createdAt = createdAt; self.isFavorite = isFavorite; self.usageCount = usageCount }
    public var displayText: String { switch value { case .text(let text): text; case .url(let url): url.absoluteString } }
}

public actor ClipboardSearch {
    private let capacity: Int; private var cache: [ClipboardSnapshot] = []
    public init(capacity: Int = 500) { self.capacity = max(1, capacity) }
    public func replace(with snapshots: [ClipboardSnapshot]) { cache = Array(snapshots.sorted(by: Self.sort).prefix(capacity)) }
    public func results(matching query: String) -> [ClipboardSnapshot] {
        let needle = Self.normalize(query)
        return cache.filter { needle.isEmpty || Self.normalize($0.displayText).contains(needle) }.sorted(by: Self.sort)
    }
    private static func normalize(_ value: String) -> String { value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
    private static func sort(_ lhs: ClipboardSnapshot, _ rhs: ClipboardSnapshot) -> Bool { if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }; if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }; return lhs.createdAt > rhs.createdAt }
}
