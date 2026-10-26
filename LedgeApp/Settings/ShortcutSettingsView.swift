import SwiftUI

struct ShortcutSettingsView: View {
    @AppStorage("ledge.hotkey.shelf") private var shelfShortcut = "Command-Option-Space"
    @AppStorage("ledge.hotkey.capture") private var captureShortcut = "Command-Option-C"
    @AppStorage("ledge.hotkey.conflict") private var conflict = false
    var resetShelfPosition: () -> Void = {}

    var body: some View {
        Form {
            Section("Global shortcuts") {
                LabeledContent("Open Shelf", value: shelfShortcut)
                LabeledContent("Quick Capture", value: captureShortcut)
                if conflict {
                    Label("A shortcut is in use by another app.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Shortcut conflict: Settings remains available from the menu bar")
                }
                Text("Ledge registers only these two exact chords. It does not monitor arbitrary keystrokes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Recovery") {
                Button("Reset Shelf Position", action: resetShelfPosition).frame(minHeight: 44)
                Text("If a display is disconnected or a shelf is off-screen, Reset Shelf Position returns it to the current display.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
