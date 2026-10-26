import Foundation

public enum CaptureSourcePolicy: String, Sendable, Codable, CaseIterable {
    case attachApplication
    case neverAttach
}

public struct CapturePreferences: Sendable, Equatable {
    public let sourcePolicy: CaptureSourcePolicy
    public init(sourcePolicy: CaptureSourcePolicy = .attachApplication) { self.sourcePolicy = sourcePolicy }
}
