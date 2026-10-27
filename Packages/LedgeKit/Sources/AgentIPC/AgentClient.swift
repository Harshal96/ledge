import Foundation
import Security
import AutomationDomain

@objc public protocol LedgeAgentProtocol {
    func request(_ data: Data, reply: @escaping @Sendable (Data) -> Void)
}

public enum AgentSecurity {
    public static let serviceName = "com.ledge.agent"
    public static func requirement(identifiers: [String]) throws -> String? {
        var code: SecCode?; var staticCode: SecStaticCode?; var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { throw PlatformError.unavailable("Cannot inspect application signing identity") }
        if let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String {
            guard team.allSatisfy({ $0.isLetter || $0.isNumber }) else { throw PlatformError.denied("Invalid signing team") }
            return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and (" + identifiers.map { "identifier \"\($0)\"" }.joined(separator: " or ") + ")"
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["LEDGE_DEVELOPMENT_IPC"] == "1" { return nil }
        #endif
        throw PlatformError.unavailable("The background runner requires a signed Ledge build. For local Debug testing, explicitly enable LEDGE_DEVELOPMENT_IPC=1 for both processes.")
    }
}

public protocol AgentTransport: Sendable {
    func call(_ method: String, _ params: JSONValue) async throws -> JSONValue
}
public extension AgentTransport {
    func call(_ method: String) async throws -> JSONValue { try await call(method, .empty) }
}
public final class AgentClient: AgentTransport, @unchecked Sendable {
    public init() {}
    public func call(_ method: String, _ params: JSONValue = .empty) async throws -> JSONValue {
        let request = try WireCoding.encoder().encode(JSONValue.object(["method": .string(method), "params": params]))
        guard request.count <= 1_048_576 else { throw PlatformError.invalid("Agent request exceeds limit") }
        let requirement = try AgentSecurity.requirement(identifiers: ["com.ledge.agent"])
        return try await withCheckedThrowingContinuation { continuation in
            let c = NSXPCConnection(machServiceName: AgentSecurity.serviceName)
            let completion = AgentReply(continuation: continuation, connection: c)
            c.remoteObjectInterface = NSXPCInterface(with: LedgeAgentProtocol.self)
            if let requirement { c.setCodeSigningRequirement(requirement) }
            c.invalidationHandler = { completion.finish(.failure(PlatformError.unavailable("Ledge runner is not connected. Enable the background runner in Automations settings."))) }
            c.interruptionHandler = c.invalidationHandler
            c.resume()
            let proxy = c.remoteObjectProxyWithErrorHandler { _ in completion.finish(.failure(PlatformError.unavailable("Background runner unavailable"))) } as? any LedgeAgentProtocol
            proxy?.request(request) { response in
                do {
                    guard response.count <= 2_097_152 else { throw PlatformError.invalid("Agent response exceeds limit") }
                    let result = try StrictJSON.decode(response, maximumBytes: 2_097_152)
                    if let message = result["error"].string { throw PlatformError.unavailable(message) }
                    completion.finish(.success(result["result"]))
                } catch { completion.finish(.failure(error)) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) { completion.finish(.failure(PlatformError.unavailable("Background runner did not reply"))) }
        }
    }
}

private final class AgentReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<JSONValue, any Error>?
    private let connection: NSXPCConnection
    init(continuation: CheckedContinuation<JSONValue, any Error>, connection: NSXPCConnection) { self.continuation = continuation; self.connection = connection }
    func finish(_ result: Result<JSONValue, any Error>) {
        let c = lock.withLock { let value = continuation; continuation = nil; return value }
        guard let c else { return }; c.resume(with: result); connection.invalidate()
    }
}
