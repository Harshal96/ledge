import Foundation
import LedgeDomain

public enum ClipboardSkipReason: Error, Sendable, Equatable { case notOptedIn, accessNotGranted, paused, excludedApplication, uncertainSource, transientOrConcealed, unsupportedContent, oversizedContent, selfWrite }
public enum ClipboardDecision: Sendable, Equatable { case allow, skip(ClipboardSkipReason) }

public struct ClipboardPolicy: Sendable {
    public static let maximumContentUTF8Bytes = 64 * 1024
    public let excludedBundleIDs: Set<String>
    public init(excludedBundleIDs: some Sequence<String>) { self.excludedBundleIDs = Set(excludedBundleIDs) }
    /// This guard intentionally requires no pasteboard inspection. Call it before declared types or content.
    public func sourceDecision(previousBundleID: String?, currentBundleID: String?) -> ClipboardDecision {
        guard let previousBundleID, let currentBundleID, previousBundleID == currentBundleID else { return .skip(.uncertainSource) }
        guard !excludedBundleIDs.contains(currentBundleID) else { return .skip(.excludedApplication) }
        return .allow
    }
    public func decision(previousBundleID: String?, currentBundleID: String?, declaredTypes: Set<PasteboardType>) -> ClipboardDecision {
        let source = sourceDecision(previousBundleID: previousBundleID, currentBundleID: currentBundleID)
        guard source == .allow else { return source }
        guard declaredTypes.isDisjoint(with: [.transient, .concealed]) else { return .skip(.transientOrConcealed) }
        guard declaredTypes.contains(.string) || declaredTypes.contains(.url) else { return .skip(.unsupportedContent) }
        return .allow
    }
    public func makeDraft(_ value: ClipboardValue, now: Date) -> Result<ShelfItemDraft, ClipboardSkipReason> {
        switch value {
        case .text(let text):
            guard text.lengthOfBytes(using: .utf8) <= Self.maximumContentUTF8Bytes else { return .failure(.oversizedContent) }
            return .success(ShelfItemDraft(kind: .clipboardText, content: .text(text), source: nil, createdAt: now, expiresAt: now.addingTimeInterval(30 * 86_400)))
        case .url(let url):
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", !url.isFileURL else { return .failure(.unsupportedContent) }
            return .success(ShelfItemDraft(kind: .clipboardURL, content: .url(url), source: nil, createdAt: now, expiresAt: now.addingTimeInterval(30 * 86_400)))
        }
    }
}
