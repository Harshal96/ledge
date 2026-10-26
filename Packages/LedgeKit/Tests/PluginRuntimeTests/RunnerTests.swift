import Foundation
import Testing
import AutomationDomain
@testable import PluginRuntime

@Test func frameParserRejectsOverflowAndMalformedJSON() throws {
    var parser = JSONRPCFramer()
    #expect(try parser.append(Data("{\"jsonrpc\":\"2.0\",\"id\":1".utf8)).isEmpty)
    #expect(try parser.append(Data(",\"result\":{}}\n".utf8)).count == 1)
    #expect(throws: (any Error).self) { try parser.append(Data(repeating: 120, count: 262_145)) }
}

@Test func localProgramUsesProtocolAndRequiresSuccessfulExit() async throws {
    let runner = ProgramRunner()
    let result = try await runner.execute(executable: "/bin/sh", arguments: ["-c", "read line; printf '%s\\n' '{\"jsonrpc\":\"2.0\",\"id\":\"run\",\"result\":{\"events\":[{\"sourceKey\":\"hello\",\"title\":\"Hello\"}]}}'"], directory: URL(fileURLWithPath: "/private/tmp"), request: .empty, timeout: 5, hostCall: { _, _ in .null })
    #expect(result.events.first?.title == "Hello")
    await #expect(throws: (any Error).self) { try await runner.execute(executable: "/bin/sh", arguments: ["-c", "exit 2"], directory: URL(fileURLWithPath: "/private/tmp"), request: .empty, timeout: 5, hostCall: { _, _ in .null }) }
}

@Test func timeoutTerminatesCooperativeProcessGroupWithoutFinalCommit() async {
    let runner = ProgramRunner()
    await #expect(throws: (any Error).self) {
        try await runner.execute(executable: "/bin/sh", arguments: ["-c", "read line; sleep 30"], directory: URL(fileURLWithPath: "/private/tmp"), request: .empty, timeout: 0.1, hostCall: { _, _ in .null })
    }
}

@Test func childCanRequestHostDataBeforeExiting() async throws {
    let program = "read initial; printf '%s\\n' '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"host.state.get\",\"params\":{}}'; read answer; printf '%s\\n' '{\"jsonrpc\":\"2.0\",\"id\":\"run\",\"result\":{\"summary\":\"round trip\"}}'"
    let result = try await ProgramRunner().execute(executable: "/bin/sh", arguments: ["-c", program], directory: URL(fileURLWithPath: "/private/tmp"), request: .empty, timeout: 1, hostCall: { method, _ in
        #expect(method == "host.state.get")
        return .object(["cursor": .number(1)])
    })
    #expect(result.summary == "round trip")
}

@Test func cancellationWinningTheLaunchGateNeverInvokesNativeCode() {
    let invocation = Invocation()
    invocation.stop(timedOut: false)
    var launched = false
    #expect(throws: (any Error).self) { try invocation.start { launched = true; return 123 } }
    #expect(!launched)
}
