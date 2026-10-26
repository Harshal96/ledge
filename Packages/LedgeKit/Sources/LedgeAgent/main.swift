import Foundation
import AutomationDomain
import AutomationHost
import AgentIPC

final class AgentService: NSObject, LedgeAgentProtocol, NSXPCListenerDelegate, @unchecked Sendable {
    private let host: AutomationHost
    init(host: AutomationHost) { self.host = host }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == getuid() else { return false }
        do {
            if let requirement = try AgentSecurity.requirement(identifiers: ["com.ledge.app", "com.ledge.cli"]) { connection.setCodeSigningRequirement(requirement) }
            connection.exportedInterface = NSXPCInterface(with: LedgeAgentProtocol.self)
            connection.exportedObject = self
            connection.resume(); return true
        } catch { return false }
    }
    func request(_ data: Data, reply: @escaping @Sendable (Data) -> Void) {
        Task {
            let response: JSONValue
            do {
                guard data.count <= 1_048_576 else { throw PlatformError.invalid("Request too large") }
                let request = try StrictJSON.decode(data)
                guard let method = request["method"].string else { throw PlatformError.invalid("Missing control method") }
                response = .object(["result": try await host.handle(method, params: request["params"])])
            } catch { response = .object(["error": .string(error.localizedDescription)]) }
            reply((try? WireCoding.encoder().encode(response)) ?? Data("{}".utf8))
        }
    }
}

let startup = DispatchSemaphore(value: 0)
nonisolated(unsafe) var service: AgentService?
nonisolated(unsafe) var startupError: String?
Task.detached {
    do { service = AgentService(host: try await AutomationHost.open()) }
    catch { startupError = error.localizedDescription }
    startup.signal()
}
startup.wait()
if let startupError { FileHandle.standardError.write(Data((startupError + "\n").utf8)); exit(1) }
let listener = NSXPCListener(machServiceName: AgentSecurity.serviceName)
listener.delegate = service
listener.resume()
dispatchMain()
