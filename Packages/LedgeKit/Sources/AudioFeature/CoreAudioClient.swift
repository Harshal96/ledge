import CoreAudio
import Foundation

/// The small HAL surface used by the feature. Numeric Core Audio object IDs
/// never leave this adapter; feature models use stable strings instead.
public protocol CoreAudioClient: Sendable {
    func currentSnapshot() async throws -> AudioSnapshot
    func snapshots() -> AsyncStream<AudioSnapshot>
    func setDefaultOutput(_ id: AudioDeviceID) async throws
    func setOutputVolume(deviceID: AudioDeviceID, value: Float) async throws
    func setOutputMuted(deviceID: AudioDeviceID, muted: Bool) async throws
    func setInputMuted(deviceID: AudioDeviceID, muted: Bool) async throws
}

/// Public Core Audio adapter. It queries capabilities before exposing a
/// control; unsupported or read-only properties remain explicit in the model.
public final class SystemCoreAudioClient: CoreAudioClient, @unchecked Sendable {
    public init() {}

    public func currentSnapshot() async throws -> AudioSnapshot {
        let output = try defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let input = try defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        var devices: [AudioDeviceSnapshot] = []
        for id in try deviceIDs() {
            devices.append(deviceSnapshot(id, outputID: output, inputID: input))
        }
        return AudioSnapshot(defaultOutputID: output.map { String($0) }, defaultInputID: input.map { String($0) }, devices: devices, fetchedAt: .now)
    }

    public func snapshots() -> AsyncStream<AudioSnapshot> {
        AsyncStream { continuation in
            Task {
                if let snapshot = try? await currentSnapshot() { continuation.yield(snapshot) }
                continuation.finish()
            }
        }
    }

    public func setDefaultOutput(_ id: AudioDeviceID) async throws {
        guard let numeric = UInt32(id) else { throw AudioControlError.deviceUnavailable }
        var value = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(numeric)
        try set(systemObject, address: &value, value: &device)
    }

    public func setOutputVolume(deviceID: AudioDeviceID, value: Float) async throws {
        try setScalar(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput, selector: kAudioDevicePropertyVolumeScalar, value: value)
    }

    public func setOutputMuted(deviceID: AudioDeviceID, muted: Bool) async throws {
        try setMute(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput, muted: muted)
    }

    public func setInputMuted(deviceID: AudioDeviceID, muted: Bool) async throws {
        try setMute(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput, muted: muted)
    }

    private let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private func deviceIDs() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size)
        guard status == noErr else { throw AudioControlError.clientFailure }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        let readStatus = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids)
        guard readStatus == noErr else { throw AudioControlError.clientFailure }
        return ids
    }

    private func defaultDevice(selector: AudioObjectPropertySelector) throws -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &id)
        if id == 0 { return nil }
        guard status == noErr else { throw AudioControlError.clientFailure }
        return id
    }

    private func deviceSnapshot(_ id: AudioObjectID, outputID: AudioObjectID?, inputID: AudioObjectID?) -> AudioDeviceSnapshot {
        let output = id == outputID
        let input = id == inputID
        return AudioDeviceSnapshot(
            id: String(id),
            name: name(for: id),
            outputVolume: output ? scalarControl(deviceID: id, scope: kAudioDevicePropertyScopeOutput, selector: kAudioDevicePropertyVolumeScalar) : .unsupported,
            outputMuted: output ? muteControl(deviceID: id, scope: kAudioDevicePropertyScopeOutput) : .unsupported,
            inputVolume: input ? scalarControl(deviceID: id, scope: kAudioDevicePropertyScopeInput, selector: kAudioDevicePropertyVolumeScalar) : .unsupported,
            inputMuted: input ? muteControl(deviceID: id, scope: kAudioDevicePropertyScopeInput) : .unsupported
        )
    }

    private func name(for id: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return "Audio Device" }
        return value.takeUnretainedValue() as String
    }

    private func scalarControl(deviceID: AudioObjectID, scope: AudioObjectPropertyScope, selector: AudioObjectPropertySelector) -> AudioControl<Float> {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMaster)
        guard AudioObjectHasProperty(deviceID, &address) else { return .unsupported }
        var value = Float32(0); var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return .unsupported }
        return isSettable(deviceID, &address) ? .writable(value) : .readOnly(value)
    }

    private func muteControl(deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> AudioControl<Bool> {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: scope, mElement: kAudioObjectPropertyElementMaster)
        guard AudioObjectHasProperty(deviceID, &address) else { return .unsupported }
        var value = UInt32(0); var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return .unsupported }
        return isSettable(deviceID, &address) ? .writable(value != 0) : .readOnly(value != 0)
    }

    private func setScalar(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, selector: AudioObjectPropertySelector, value: Float) throws {
        guard let id = UInt32(deviceID) else { throw AudioControlError.deviceUnavailable }
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMaster)
        guard AudioObjectHasProperty(id, &address), isSettable(id, &address) else { throw AudioControlError.unsupported }
        var value = max(0, min(1, value)); try set(id, address: &address, value: &value)
    }

    private func setMute(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, muted: Bool) throws {
        guard let id = UInt32(deviceID) else { throw AudioControlError.deviceUnavailable }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: scope, mElement: kAudioObjectPropertyElementMaster)
        guard AudioObjectHasProperty(id, &address), isSettable(id, &address) else { throw AudioControlError.unsupported }
        var value: UInt32 = muted ? 1 : 0; try set(id, address: &address, value: &value)
    }

    private func set<T>(_ object: AudioObjectID, address: inout AudioObjectPropertyAddress, value: inout T) throws {
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectSetPropertyData(object, &address, 0, nil, size, &value)
        guard status == noErr else { throw AudioControlError.clientFailure }
    }

    private func isSettable(_ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }
}
