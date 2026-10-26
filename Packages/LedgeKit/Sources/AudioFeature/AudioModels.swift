import Foundation

/// The stable, string form used at the feature boundary. Core Audio's numeric
/// object IDs are deliberately kept inside `SystemCoreAudioClient`.
public typealias AudioDeviceID = String

/// A property can only be changed when Core Audio reports that it is present
/// and settable. A read-only property still carries its last observed value so
/// the UI can explain why the control is disabled.
public enum AudioControl<Value: Sendable & Equatable>: Sendable, Equatable {
    case writable(Value)
    case readOnly(Value)
    case unsupported

    public var value: Value? {
        switch self {
        case let .writable(value), let .readOnly(value): value
        case .unsupported: nil
        }
    }

    public var isWritable: Bool {
        if case .writable = self { return true }
        return false
    }
}

public struct AudioDeviceSnapshot: Identifiable, Sendable, Equatable {
    public let id: AudioDeviceID
    public let name: String
    public let outputVolume: AudioControl<Float>
    public let outputMuted: AudioControl<Bool>
    public let inputVolume: AudioControl<Float>
    public let inputMuted: AudioControl<Bool>

    public init(
        id: AudioDeviceID,
        name: String,
        outputVolume: AudioControl<Float> = .unsupported,
        outputMuted: AudioControl<Bool> = .unsupported,
        inputVolume: AudioControl<Float> = .unsupported,
        inputMuted: AudioControl<Bool> = .unsupported
    ) {
        self.id = id
        self.name = name
        self.outputVolume = outputVolume
        self.outputMuted = outputMuted
        self.inputVolume = inputVolume
        self.inputMuted = inputMuted
    }

    public static func fixture(
        id: AudioDeviceID = "speaker",
        name: String = "Built-in Output",
        outputVolume: AudioControl<Float> = .writable(0.5),
        outputMuted: AudioControl<Bool> = .writable(false),
        inputVolume: AudioControl<Float> = .writable(0.5),
        inputMuted: AudioControl<Bool> = .writable(false)
    ) -> AudioDeviceSnapshot {
        AudioDeviceSnapshot(id: id, name: name, outputVolume: outputVolume, outputMuted: outputMuted, inputVolume: inputVolume, inputMuted: inputMuted)
    }
}

public struct AudioSnapshot: Sendable, Equatable {
    public let defaultOutputID: AudioDeviceID?
    public let defaultInputID: AudioDeviceID?
    public let devices: [AudioDeviceSnapshot]
    public let fetchedAt: Date?

    public init(
        defaultOutputID: AudioDeviceID?,
        defaultInputID: AudioDeviceID? = nil,
        devices: [AudioDeviceSnapshot] = [],
        fetchedAt: Date? = nil
    ) {
        self.defaultOutputID = defaultOutputID
        self.defaultInputID = defaultInputID
        self.devices = devices
        self.fetchedAt = fetchedAt
    }

    public static let empty = AudioSnapshot(defaultOutputID: nil, defaultInputID: nil)

    public static func fixture(
        defaultOutputID: AudioDeviceID? = "speaker",
        defaultInputID: AudioDeviceID? = "microphone",
        outputVolume: AudioControl<Float> = .writable(0.5),
        outputMute: AudioControl<Bool> = .writable(false),
        inputVolume: AudioControl<Float> = .writable(0.5),
        inputMute: AudioControl<Bool> = .writable(false),
        devices: [AudioDeviceSnapshot]? = nil
    ) -> AudioSnapshot {
        let outputID = defaultOutputID ?? "speaker"
        let inputID = defaultInputID ?? "microphone"
        let fixtureDevices = devices ?? [
            AudioDeviceSnapshot(id: outputID, name: "Built-in Output", outputVolume: outputVolume, outputMuted: outputMute),
            AudioDeviceSnapshot(id: inputID, name: "Built-in Microphone", inputVolume: inputVolume, inputMuted: inputMute)
        ]
        return AudioSnapshot(defaultOutputID: defaultOutputID, defaultInputID: defaultInputID, devices: fixtureDevices)
    }

    public func device(id: AudioDeviceID?) -> AudioDeviceSnapshot? {
        guard let id else { return nil }
        return devices.first { $0.id == id }
    }
}

public enum AudioControlError: Error, Sendable, Equatable {
    case unsupported
    case deviceUnavailable
    case invalidValue
    case confirmationTimedOut
    case clientFailure
}

public enum NowPlayingUnavailableReason: String, Sendable, Equatable {
    case noPublicCrossAppAPI
}

public enum TransportCommand: String, Sendable, Equatable, CaseIterable {
    case playPause
    case next
    case previous
}

public enum NowPlayingSnapshot: Sendable, Equatable {
    case unavailable(reason: NowPlayingUnavailableReason)
}

public enum NowPlayingError: Error, Sendable, Equatable {
    case unavailable(NowPlayingUnavailableReason)
}

public protocol NowPlayingProviding: Sendable {
    func snapshots() -> AsyncStream<NowPlayingSnapshot>
    func perform(_ command: TransportCommand) async throws
}
