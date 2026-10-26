import SwiftUI

public struct AudioCardView: View {
    public let snapshot: AudioSnapshot
    public let setOutputVolume: (Float) -> Void
    public let toggleOutputMute: (Bool) -> Void
    public let toggleInputMute: (Bool) -> Void

    public init(snapshot: AudioSnapshot, setOutputVolume: @escaping (Float) -> Void = { _ in }, toggleOutputMute: @escaping (Bool) -> Void = { _ in }, toggleInputMute: @escaping (Bool) -> Void = { _ in }) {
        self.snapshot = snapshot; self.setOutputVolume = setOutputVolume; self.toggleOutputMute = toggleOutputMute; self.toggleInputMute = toggleInputMute
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Controls").font(.headline)
            if let output = snapshot.device(id: snapshot.defaultOutputID) {
                Text(output.name).font(.subheadline)
                if let volume = output.outputVolume.value {
                    Slider(value: Binding(get: { Double(volume) }, set: { setOutputVolume(Float($0)) }), in: 0...1) {
                        Text("Output volume")
                    }.disabled(!output.outputVolume.isWritable).accessibilityLabel("Output volume")
                } else { Text("Output volume is not supported").foregroundStyle(.secondary) }
                Toggle("Mute output", isOn: Binding(get: { output.outputMuted.value ?? false }, set: toggleOutputMute)).disabled(!output.outputMuted.isWritable)
            } else { Text("No output device available").foregroundStyle(.secondary) }
            if let input = snapshot.device(id: snapshot.defaultInputID) {
                Toggle("Mute input device", isOn: Binding(get: { input.inputMuted.value ?? false }, set: toggleInputMute)).disabled(!input.inputMuted.isWritable)
            }
            Text("Universal cross-app Now Playing is unavailable through public macOS APIs.").font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 300)
    }
}
