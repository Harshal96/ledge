import Foundation
import Darwin
import AutomationDomain

/// Executes explicitly trusted local code. Pipes and process groups supervise
/// cooperative programs; they do not sandbox native code running as this user.
public final class ProgramRunner: @unchecked Sendable {
    public typealias HostCall = @Sendable (String, JSONValue) async throws -> JSONValue
    private let lock = NSLock()
    private var active: [String: Invocation] = [:]
    public init() {}

    public func execute(executable: String, arguments: [String], directory: URL, request: JSONValue, timeout: Double, runID: String = UUID().uuidString, hostCall: @escaping HostCall) async throws -> RunResult {
        try Task.checkCancellation()
        let invocation = Invocation()
        lock.withLock { active[runID] = invocation }
        defer { _ = lock.withLock { active.removeValue(forKey: runID) } }
        return try await withTaskCancellationHandler {
            try await Task.detached { try self.run(executable, arguments, directory, request, timeout, invocation, hostCall) }.value
        } onCancel: { invocation.stop(timedOut: false) }
    }
    public func cancel(runID: String) { lock.withLock { active[runID] }?.stop(timedOut: false) }
    public func cancelAll() { lock.withLock { Array(active.values) }.forEach { $0.stop(timedOut: false) } }

    private func run(_ executable: String, _ arguments: [String], _ directory: URL, _ request: JSONValue, _ timeout: Double, _ invocation: Invocation, _ hostCall: @escaping HostCall) throws -> RunResult {
        guard executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable), (0.05...900).contains(timeout) else { throw PlatformError.invalid("Choose an absolute executable and a bounded timeout") }
        var input: [Int32] = [0, 0], output: [Int32] = [0, 0], errors: [Int32] = [0, 0]
        guard pipe(&input) == 0 else { throw PlatformError.unavailable("Cannot create stdin pipe") }
        guard pipe(&output) == 0 else { input.forEach { Darwin.close($0) }; throw PlatformError.unavailable("Cannot create stdout pipe") }
        guard pipe(&errors) == 0 else { (input + output).forEach { Darwin.close($0) }; throw PlatformError.unavailable("Cannot create stderr pipe") }
        _ = fcntl(input[1], F_SETNOSIGPIPE, 1)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_adddup2(&actions, input[0], STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errors[1], STDERR_FILENO)
        guard posix_spawn_file_actions_addchdir_np(&actions, directory.path) == 0 else { (input + output + errors).forEach { Darwin.close($0) }; throw PlatformError.invalid("Invalid working directory") }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { $0.withCString { strdup($0) } } + [nil]
        var environmentStrings: [String] = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin", "HOME=\(NSHomeDirectory())", "LANG=en_US.UTF-8", "PYTHONUNBUFFERED=1", "PYTHONDONTWRITEBYTECODE=1"]
        if let sdk = Self.pythonSDKPath { environmentStrings.append("PYTHONPATH=\(sdk)") }
        var environment: [UnsafeMutablePointer<CChar>?] = environmentStrings.map { $0.withCString { strdup($0) } } + [nil]
        defer { argv.forEach { free($0) }; environment.forEach { free($0) } }
        var pid: pid_t = 0
        do {
            pid = try invocation.start {
                var child: pid_t = 0
                let status = posix_spawn(&child, executable, &actions, &attributes, &argv, &environment)
                guard status == 0 else { throw PlatformError.unavailable("Program launch failed (\(status))") }
                return child
            }
        } catch { (input + output + errors).forEach { Darwin.close($0) }; throw error }
        Darwin.close(input[0]); Darwin.close(output[1]); Darwin.close(errors[1])
        let writer = FileHandle(fileDescriptor: input[1], closeOnDealloc: true)
        let reader = FileHandle(fileDescriptor: output[0], closeOnDealloc: true)
        let errorReader = FileHandle(fileDescriptor: errors[0], closeOnDealloc: true)
        var reaped = false
        defer {
            try? writer.close(); try? reader.close(); try? errorReader.close()
            if !reaped { invocation.stop(timedOut: false); var status: Int32 = 0; while waitpid(pid, &status, 0) < 0 && errno == EINTR {} }
            invocation.finished()
        }
        let watchdog = DispatchWorkItem { invocation.stop(timedOut: true) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer { watchdog.cancel() }
        DispatchQueue.global().async {
            var count = 0
            while let chunk = try? errorReader.read(upToCount: 8192), !chunk.isEmpty {
                count += chunk.count
                if count > 1_048_576 { invocation.stop(timedOut: false); break }
            }
        }
        try write(.object(["jsonrpc": .string("2.0"), "id": .string("run"), "method": .string("run"), "params": request]), to: writer)
        var framer = JSONRPCFramer(); var final: RunResult?
        while true {
            // Foundation's read(upToCount:) can wait to fill the requested
            // buffer on a pipe. JSON-RPC peers wait for a reply before writing
            // more, so use one POSIX read of currently available bytes.
            let chunk = try readAvailable(reader.fileDescriptor)
            if chunk.isEmpty { break }
            for frame in try framer.append(chunk) {
                guard frame["jsonrpc"].string == "2.0" else { throw PlatformError.invalid("Expected JSON-RPC 2.0") }
                if let method = frame["method"].string {
                    let answer = BlockingAnswer()
                    Task {
                        do { answer.set(.success(try await hostCall(method, frame["params"]))) }
                        catch { answer.set(.failure(error)) }
                    }
                    guard answer.ready.wait(timeout: .now() + timeout) == .success else { throw PlatformError.timeout }
                    let response: JSONValue
                    switch answer.get() {
                    case let .success(value): response = .object(["jsonrpc": .string("2.0"), "id": frame["id"], "result": value])
                    case let .failure(error): response = .object(["jsonrpc": .string("2.0"), "id": frame["id"], "error": .object(["code": .number(-32000), "message": .string(error.localizedDescription)])])
                    }
                    try write(response, to: writer)
                } else {
                    guard frame["id"] == .string("run"), frame["error"] == .null, final == nil, frame["result"].object != nil else { throw PlatformError.invalid("Invalid or repeated final response") }
                    let result = frame["result"]
                    var allowed: Set<String> = ["events", "state", "recordMutations", "summary"]
                    if request["hostProtocol"].string == "2" { allowed.insert("viewSnapshot") }
                    try Validation.keys(result, allowed: allowed)
                    for event in result["events"].array ?? [] { _ = try HostEvent.validated(data: WireCoding.encoder().encode(event)) }
                    final = try WireCoding.decoder().decode(RunResult.self, from: WireCoding.encoder().encode(result))
                }
            }
        }
        try framer.finish()
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 { if errno != EINTR { throw PlatformError.unavailable("Cannot reap program") } }
        reaped = true
        if invocation.timedOut { throw PlatformError.timeout }
        if invocation.wasCancelled { throw PlatformError.cancelled }
        guard status == 0, let final else { throw PlatformError.invalid("Program failed or produced no final result") }
        return final
    }
    private func write(_ value: JSONValue, to handle: FileHandle) throws {
        var data = try WireCoding.encoder().encode(value)
        guard data.count <= 262_144 else { throw PlatformError.invalid("Host response exceeds 256 KiB") }
        data.append(10); try handle.write(contentsOf: data)
    }
    private func readAvailable(_ descriptor: Int32) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count >= 0 { return Data(buffer.prefix(count)) }
            if errno != EINTR { throw PlatformError.unavailable("Plugin pipe read failed") }
        }
    }
    public static var pythonSDKPath: String? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        let bundled = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/PluginSDK/python")
        if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("ledge_sdk/__init__.py").path) { return bundled.path }
        #if DEBUG
        let development = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SDKs/python")
        if FileManager.default.fileExists(atPath: development.appendingPathComponent("ledge_sdk/__init__.py").path) { return development.path }
        #endif
        return nil
    }
}

final class Invocation: @unchecked Sendable {
    private let lock = NSLock(); private var pid: pid_t?; private var cancelled = false; private var timeout = false
    var timedOut: Bool { lock.withLock { timeout } }
    var wasCancelled: Bool { lock.withLock { cancelled } }
    /// Cancellation and launch have one ordering point: if stop wins the lock,
    /// native code is never launched. If spawn wins, stop sees its registered PID.
    func start(_ launch: () throws -> pid_t) throws -> pid_t {
        try lock.withLock {
            guard !cancelled else { throw PlatformError.cancelled }
            let value = try launch(); pid = value; return value
        }
    }
    func finished() { lock.withLock { pid = nil } }
    func stop(timedOut: Bool) {
        let value = lock.withLock { cancelled = true; timeout = timeout || timedOut; return pid }
        guard let value else { return }; kill(-value, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [self] in
            lock.withLock { if pid == value { kill(-value, SIGKILL) } }
        }
    }
}

private final class BlockingAnswer: @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock(); private var result: Result<JSONValue, any Error>?
    func set(_ value: Result<JSONValue, any Error>) { lock.withLock { result = value }; ready.signal() }
    func get() -> Result<JSONValue, any Error> { lock.withLock { result! } }
}
