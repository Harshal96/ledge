import Foundation

public enum HostDestination: Sendable, Equatable {
    case library, settings, instance(String)
}

public struct ShellPreferences: Sendable {
    public let createsStatusItem = false
    public let initialDestination = HostDestination.library
    public init(legacyMenuIconEnabled: Bool = false) {}
}

public enum HostAvailability: Sendable, Equatable {
    case ready, unavailable(String)
    public var canBrowseLibrary: Bool { true }
    public var canRunApps: Bool { self == .ready }
}

public struct BuildIdentity: Codable, Sendable, Equatable {
    public let version: String
    public let build: String
    public let commit: String
    public let executableURL: URL
    public init(version: String, build: String, commit: String, executableURL: URL) {
        self.version = version; self.build = build; self.commit = commit; self.executableURL = executableURL
    }
    public static var current: BuildIdentity {
        let stamp = Bundle.main.url(forResource: "LedgeBuildCommit", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) }
        return .init(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development", build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0", commit: stamp ?? Bundle.main.object(forInfoDictionaryKey: "LedgeCommit") as? String ?? "unversioned", executableURL: Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
    }
}
