import Foundation
import Testing
@testable import AudioFeature

@Test("Unsupported input mute is never emulated with input volume")
func unsupportedMicMute() async throws {
    let client = FakeCoreAudioClient(
        snapshot: .fixture(inputVolume: .writable(0.7), inputMute: .unsupported)
    )
    let service = AudioHardwareService(client: client)

    await #expect(throws: AudioControlError.unsupported) {
        try await service.setInputDeviceMuted(true)
    }
    #expect(await client.inputVolumeWriteCount == 0)
}

@Test("Route switch completes only after matching listener snapshot")
func routeSwitchNeedsConfirmation() async throws {
    let client = FakeCoreAudioClient(snapshot: .fixture(defaultOutputID: "speaker", devices: [
        .fixture(id: "speaker"), .fixture(id: "headphones")
    ]))
    let service = AudioHardwareService(client: client, confirmationTimeout: .milliseconds(200))
    let task = Task { try await service.setDefaultOutput("headphones") }

    try await Task.sleep(for: .milliseconds(20))
    #expect(!task.isCancelled)

    await client.emit(.fixture(defaultOutputID: "headphones"))
    try await task.value
    #expect(await service.latest.defaultOutputID == "headphones")
}

@Test("A route write times out without a matching listener snapshot")
func routeSwitchTimeoutPreservesLastConfirmedState() async throws {
    let client = FakeCoreAudioClient(snapshot: .fixture(defaultOutputID: "speaker", devices: [
        .fixture(id: "speaker"), .fixture(id: "headphones")
    ]))
    let service = AudioHardwareService(client: client, confirmationTimeout: .milliseconds(20))

    await #expect(throws: AudioControlError.confirmationTimedOut) {
        try await service.setDefaultOutput("headphones")
    }
    #expect(await service.latest.defaultOutputID == "speaker")
}

@Test("Read-only output controls are not written")
func readOnlyOutputVolumeIsRejected() async throws {
    let client = FakeCoreAudioClient(
        snapshot: .fixture(outputVolume: .readOnly(0.5))
    )
    let service = AudioHardwareService(client: client)

    await #expect(throws: AudioControlError.unsupported) {
        try await service.setOutputVolume(0.8)
    }
    #expect(await client.outputVolumeWriteCount == 0)
}

private actor FakeCoreAudioClient: CoreAudioClient {
    private(set) var current: AudioSnapshot
    nonisolated let stream: AsyncStream<AudioSnapshot>
    private let continuation: AsyncStream<AudioSnapshot>.Continuation

    private(set) var inputVolumeWriteCount = 0
    private(set) var outputVolumeWriteCount = 0

    init(snapshot: AudioSnapshot) {
        self.current = snapshot
        let pair = AsyncStream<AudioSnapshot>.makeStream(of: AudioSnapshot.self, bufferingPolicy: .bufferingNewest(8))
        self.stream = pair.stream
        self.continuation = pair.continuation
    }

    func currentSnapshot() async throws -> AudioSnapshot { current }
    nonisolated func snapshots() -> AsyncStream<AudioSnapshot> { stream }

    func emit(_ snapshot: AudioSnapshot) {
        current = snapshot
        continuation.yield(snapshot)
    }

    func setDefaultOutput(_ id: String) async throws {}

    func setOutputVolume(deviceID: String, value: Float) async throws {
        outputVolumeWriteCount += 1
    }

    func setOutputMuted(deviceID: String, muted: Bool) async throws {}

    func setInputMuted(deviceID: String, muted: Bool) async throws {
        inputVolumeWriteCount += 1
    }
}
