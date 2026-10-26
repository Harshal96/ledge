import Foundation

#if canImport(AppKit)
import AppKit

/// Best-effort attribution for the activation interval surrounding a pasteboard
/// change. It is queried before pasteboard types or content are read.
public actor WorkspaceActiveApplicationProvider: ActiveApplicationProviding {
    private var previous: String?
    public init() {}
    public func activationBundleIDs() async -> (previous: String?, current: String?) {
        let current = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        defer { previous = current }
        return (previous, current)
    }
}
#endif
