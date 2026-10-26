import Foundation
import LedgeDomain
#if canImport(AppKit)
import AppKit
#endif

public struct JoinURLParser: Sendable {
    private let knownHTTPSHosts: Set<String>
    private let policy: ExternalURLPolicy
    public init(knownHTTPSHosts: Set<String> = ["meet.google.com", "zoom.us", "teams.microsoft.com", "webex.com"], policy: ExternalURLPolicy = ExternalURLPolicy()) { self.knownHTTPSHosts = Set(knownHTTPSHosts.map { $0.lowercased() }); self.policy = policy }
    public func joinURL(for meeting: Meeting) -> JoinURL? {
        [meeting.url, meeting.location, meeting.notes].compactMap { $0 }.lazy.compactMap(parse).first
    }
    public func parse(_ text: String) -> JoinURL? {
        guard let candidate = firstHTTPURL(in: text), case let .success(url) = policy.validate(candidate), let host = url.host?.lowercased() else { return nil }
        return JoinURL(url: url, requiresConfirmation: !isKnownHost(host))
    }
    private func firstHTTPURL(in text: String) -> String? {
        if case .success = policy.validate(text) { return text }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)).flatMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
    private func isKnownHost(_ host: String) -> Bool { knownHTTPSHosts.contains(host) || knownHTTPSHosts.contains(where: { host.hasSuffix("." + $0) }) }
}

#if canImport(AppKit)
@MainActor public final class WorkspaceMeetingOpener {
    private let policy: ExternalURLPolicy
    public init(policy: ExternalURLPolicy = ExternalURLPolicy()) { self.policy = policy }

    @discardableResult public func open(_ join: JoinURL, confirmedHost: String? = nil) -> Bool {
        guard case let .success(validated) = policy.validate(join.url.absoluteString), validated == join.url else { return false }
        guard !join.requiresConfirmation || confirmedHost?.lowercased() == validated.host?.lowercased() else { return false }
        return NSWorkspace.shared.open(validated)
    }
}
#endif
