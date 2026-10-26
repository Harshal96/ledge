import Foundation

public actor AudioHardwareService {
    public private(set) var latest: AudioSnapshot = .empty
    private let client: any CoreAudioClient
    private let confirmationTimeout: Duration
    private var listenerTask: Task<Void, Never>?
    private var listenerStarted = false

    public init(client: any CoreAudioClient, confirmationTimeout: Duration = .seconds(2)) {
        self.client = client
        self.confirmationTimeout = confirmationTimeout
    }

    deinit { listenerTask?.cancel() }

    public func refresh() async throws { startListenerIfNeeded(); latest = try await client.currentSnapshot() }

    public func setDefaultOutput(_ id: AudioDeviceID) async throws {
        try await ensureSnapshot()
        guard latest.device(id: id) != nil else { throw AudioControlError.deviceUnavailable }
        try await client.setDefaultOutput(id)
        try await confirm { $0.defaultOutputID == id }
    }

    public func setOutputVolume(_ value: Float) async throws {
        try await ensureSnapshot()
        guard let id = latest.defaultOutputID, let control = latest.device(id: id)?.outputVolume, control.isWritable else { throw AudioControlError.unsupported }
        guard value.isFinite else { throw AudioControlError.invalidValue }
        try await client.setOutputVolume(deviceID: id, value: max(0, min(1, value)))
        try await confirm { snapshot in
            guard let observed = snapshot.device(id: id)?.outputVolume.value else { return false }
            return abs(observed - max(0, min(1, value))) < 0.01
        }
    }

    public func setOutputMuted(_ muted: Bool) async throws {
        try await ensureSnapshot()
        guard let id = latest.defaultOutputID, latest.device(id: id)?.outputMuted.isWritable == true else { throw AudioControlError.unsupported }
        try await client.setOutputMuted(deviceID: id, muted: muted)
        try await confirm { $0.device(id: id)?.outputMuted.value == muted }
    }

    public func setInputDeviceMuted(_ muted: Bool) async throws {
        try await ensureSnapshot()
        guard let id = latest.defaultInputID, latest.device(id: id)?.inputMuted.isWritable == true else { throw AudioControlError.unsupported }
        try await client.setInputMuted(deviceID: id, muted: muted)
        try await confirm { $0.device(id: id)?.inputMuted.value == muted }
    }

    private func ensureSnapshot() async throws {
        startListenerIfNeeded()
        if latest.devices.isEmpty { try await refresh() }
    }

    private func startListenerIfNeeded() {
        guard !listenerStarted else { return }
        listenerStarted = true
        let stream = client.snapshots()
        listenerTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in stream { await self.accept(snapshot) }
        }
    }

    private func accept(_ snapshot: AudioSnapshot) { latest = snapshot }

    private func confirm(_ predicate: @escaping (AudioSnapshot) -> Bool) async throws {
        if predicate(latest) { return }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: confirmationTimeout)
        while clock.now < deadline {
            if predicate(latest) { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        guard predicate(latest) else { throw AudioControlError.confirmationTimedOut }
    }
}
