import Foundation
import AutomationDomain

public struct JSONRPCFramer: Sendable {
    private var pending = Data()
    private var total = 0
    public init() {}
    public mutating func append(_ bytes: Data) throws -> [JSONValue] {
        total += bytes.count
        guard total <= 2_097_152 else { throw PlatformError.invalid("Protocol output exceeds 2 MiB") }
        pending.append(bytes); var frames: [JSONValue] = []
        while let end = pending.firstIndex(of: 10) {
            let frame = Data(pending[..<end]); pending.removeSubrange(...end)
            guard frame.count <= 262_144 else { throw PlatformError.invalid("Protocol frame exceeds 256 KiB") }
            frames.append(try StrictJSON.decode(frame))
        }
        guard pending.count <= 262_144 else { throw PlatformError.invalid("Protocol frame exceeds 256 KiB") }
        return frames
    }
    public func finish() throws { guard pending.isEmpty else { throw PlatformError.invalid("Incomplete protocol frame") } }
}
