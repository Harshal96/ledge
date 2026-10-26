import Foundation

public struct SensitiveAppsPolicy: Sendable, Codable, Equatable {
    public let excludedBundleIDs: Set<String>
    public init(excludedBundleIDs: some Sequence<String>) { self.excludedBundleIDs = Set(excludedBundleIDs) }
    public static let bundledDefault = SensitiveAppsPolicy(excludedBundleIDs: ["com.1password.1password", "com.apple.keychainaccess", "com.agilebits.onepassword7"])
}
