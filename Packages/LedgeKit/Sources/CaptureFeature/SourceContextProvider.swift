import AppKit
import LedgeDomain

@MainActor
public protocol SourceContextProviding: AnyObject {
    func snapshot(at date: Date) async -> SourceContext?
}

@MainActor
public final class FrontmostApplicationSourceContextProvider: SourceContextProviding {
    public init() {}
    public func snapshot(at date: Date) async -> SourceContext? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        return SourceContext(bundleIdentifier: application.bundleIdentifier, applicationName: application.localizedName, capturedAt: date)
    }
}
