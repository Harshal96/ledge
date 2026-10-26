import Foundation
import Observation
import LedgeDomain

@MainActor public protocol ClipboardHistoryProviding: Sendable { func snapshots() -> AsyncStream<ClipboardSnapshot> }

@MainActor @Observable
public final class ClipboardStore: ClipboardHistoryProviding {
    public private(set) var entries: [ClipboardSnapshot] = []
    private let repository: any ShelfRepository; private let search: ClipboardSearch
    public init(repository: any ShelfRepository, search: ClipboardSearch = ClipboardSearch()) { self.repository = repository; self.search = search }
    public func reload() async {
        let items = (try? await repository.list(ShelfQuery())) ?? []
        let snapshots = items.compactMap { item -> ClipboardSnapshot? in
            switch item.content { case .text(let text) where item.kind == .clipboardText: ClipboardSnapshot(id: item.id, value: .text(text), createdAt: item.createdAt, isFavorite: item.isFavorite, usageCount: 0); case .url(let url) where item.kind == .clipboardURL: ClipboardSnapshot(id: item.id, value: .url(url), createdAt: item.createdAt, isFavorite: item.isFavorite, usageCount: 0); default: nil }
        }
        entries = Array(snapshots.sorted { $0.createdAt > $1.createdAt }.prefix(500)); await search.replace(with: entries)
    }
    public func snapshots() -> AsyncStream<ClipboardSnapshot> {
        let values = entries
        return AsyncStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        }
    }
    public func results(matching query: String) async -> [ClipboardSnapshot] { await search.results(matching: query) }
    public func setFavorite(_ entry: ClipboardSnapshot, isFavorite: Bool) async { guard isFavorite == false || entries.filter(\.isFavorite).count < 100 else { return }; _ = try? await repository.setFavorite(id: entry.id, isFavorite: isFavorite); await reload() }
    public func delete(_ entry: ClipboardSnapshot) async { try? await repository.delete(id: entry.id); await reload() }
    public func clearAll() async { for entry in entries { try? await repository.delete(id: entry.id) }; entries = []; await search.replace(with: []) }
    public func clearExpired(now: Date = .now) async { _ = try? await repository.purgeExpired(before: now); await reload() }
}
