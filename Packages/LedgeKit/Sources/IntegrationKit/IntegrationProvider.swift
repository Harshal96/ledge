import Foundation
import AutomationDomain

public protocol IntegrationProvider: Sendable {
    var identifier: String { get }
    func requiredCapability(for operation: String) -> String?
    func verify(token: String) async throws -> JSONValue
    func call(operation: String, parameters: JSONValue, account: String, repositories: [String]) async throws -> JSONValue
}
public struct UnavailableIntegrationProvider: IntegrationProvider {
    public var identifier: String { "unavailable" }
    public init() {}
    public func requiredCapability(for operation: String) -> String? { nil }
    public func verify(token: String) async throws -> JSONValue { throw PlatformError.unavailable("Install a connection provider first") }
    public func call(operation: String, parameters: JSONValue, account: String, repositories: [String]) async throws -> JSONValue { throw PlatformError.unavailable("Connection provider unavailable") }
}
