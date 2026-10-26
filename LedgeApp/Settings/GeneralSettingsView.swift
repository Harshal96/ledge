import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var permissionCenter: PermissionCenter
    @ObservedObject var loginItemController: LoginItemController
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(isOn: Binding(
                    get: { loginItemController.isEnabled },
                    set: { loginItemController.setEnabled($0) }
                )) {
                    Label("Launch at Login", systemImage: "arrow.clockwise")
                }
                .accessibilityHint("Uses the public macOS Login Items service. Approval may be required.")
                if loginItemController.state == .requiresApproval {
                    HStack {
                        Image(systemName: differentiateWithoutColor ? "exclamationmark.triangle" : "exclamationmark.circle")
                        Text("Approval is required in System Settings.")
                        Button("Open Login Items") { loginItemController.openSystemSettings() }
                    }
                    .foregroundStyle(.secondary)
                }
                if let error = loginItemController.lastError {
                    Text(error.localizedDescription).foregroundStyle(.secondary).accessibilityLabel("Launch at Login status: \(error.localizedDescription)")
                }
            }
            Section("Shelf") {
                LabeledContent("Shelf shortcut", value: "Command-Option-Space")
                LabeledContent("Quick Capture", value: "Command-Option-C")
                Text("Shortcuts can be changed from the Shortcuts tab. A conflict never prevents Ledge from opening from the menu bar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Permissions") {
                Text("Permissions are requested only after you choose a feature. Ledge does not request access during launch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Recovery remains available: open Settings from the menu-bar item or quit Ledge at any time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .accessibilityElement(children: .contain)
    }
}
