import Foundation

public enum PasteboardAccessState: Sendable, Equatable { case `default`, ask, alwaysAllow, alwaysDeny, legacyUnavailable }
public enum PasteboardType: String, Sendable, Hashable { case string, url, transient, concealed }
public enum ClipboardValue: Sendable, Hashable { case text(String), url(URL) }

/// The only clipboard boundary used by the feature. Content reads are deliberately separate from type inspection.
public protocol PasteboardClient: Sendable {
    var changeCount: Int { get async }
    var accessState: PasteboardAccessState { get async }
    var declaredTypes: Set<PasteboardType> { get async }
    func readText(maximumUTF8Bytes: Int) async -> String?
    func readURL() async -> URL?
    func write(_ value: ClipboardValue) async -> Int
    func userInitiatedAccessProbe() async -> PasteboardAccessState
}

#if canImport(AppKit)
import AppKit

/// AppKit adapter intentionally reads only the requested representation; monitoring must call policy first.
public actor SystemPasteboardClient: PasteboardClient {
    private let pasteboard: NSPasteboard
    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    public var changeCount: Int { pasteboard.changeCount }
    public var accessState: PasteboardAccessState {
        if #available(macOS 15.4, *) {
            switch pasteboard.accessBehavior {
            case .default: .default
            case .ask: .ask
            case .alwaysAllow: .alwaysAllow
            case .alwaysDeny: .alwaysDeny
            @unknown default: .alwaysDeny
            }
        } else { .legacyUnavailable }
    }
    public var declaredTypes: Set<PasteboardType> {
        Set((pasteboard.types ?? []).compactMap { type in
            if type == .string { return .string }
            if type == .URL { return .url }
            if type.rawValue.localizedCaseInsensitiveContains("transient") { return .transient }
            if type.rawValue.localizedCaseInsensitiveContains("concealed") { return .concealed }
            return nil
        })
    }
    public func readText(maximumUTF8Bytes: Int) async -> String? {
        guard let value = pasteboard.string(forType: .string), value.lengthOfBytes(using: .utf8) <= maximumUTF8Bytes else { return nil }
        return value
    }
    public func readURL() async -> URL? { pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL }
    public func write(_ value: ClipboardValue) async -> Int {
        pasteboard.clearContents()
        switch value { case .text(let text): pasteboard.setString(text, forType: .string); case .url(let url): pasteboard.writeObjects([url as NSURL]) }
        return pasteboard.changeCount
    }
    public func userInitiatedAccessProbe() async -> PasteboardAccessState { _ = pasteboard.types; return accessState }
}
#endif
