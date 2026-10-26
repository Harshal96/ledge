import SwiftUI

struct PrivacySettingsView: View {
    @ObservedObject var permissionCenter: PermissionCenter
    @AppStorage("ledge.capture.attachSourceApp") private var attachSourceApp = true
    @AppStorage("ledge.clipboard.paused") private var clipboardPaused = false
    @AppStorage("ledge.clipboard.enabled") private var clipboardEnabled = false
    @AppStorage("ledge.clipboard.retentionDays") private var retentionDays = 30
    @State private var excludedBundleIDs = ""

    var body: some View {
        Form {
            Section("Feature access") {
                PermissionRow(kind: .calendar, permissionCenter: permissionCenter, explanation: "Shows the next meeting only after you enable Meetings.")
                PermissionRow(kind: .screenCapture, permissionCenter: permissionCenter, explanation: "Requested only when you choose Capture Screenshot.")
                PermissionRow(kind: .pasteboard, permissionCenter: permissionCenter, explanation: "Ledge reads only after an explicit opt-in and an allowed pasteboard state.")
            }
            Section("Capture context") {
                Toggle("Attach the frontmost application", isOn: $attachSourceApp)
                    .accessibilityHint("Disabling this prevents future captures from attaching the source application.")
                Text("Ledge never reads selected text, window titles, or browser state. A URL is attached only when you enter it in a capture.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Clipboard") {
                Toggle("Enable clipboard shelf", isOn: $clipboardEnabled)
                Toggle("Pause clipboard monitoring", isOn: $clipboardPaused).disabled(!clipboardEnabled)
                Stepper(value: $retentionDays, in: 1...365) { Text("Retention: \(retentionDays) days") }
                TextField("Excluded bundle IDs (comma separated)", text: $excludedBundleIDs)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Excluded application bundle IDs")
                Text("Best-effort exclusions are stored locally. Clear Clipboard History removes clipboard items without changing macOS permission decisions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    @ObservedObject var permissionCenter: PermissionCenter
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(kind.title, systemImage: kind == .calendar ? "calendar" : kind == .screenCapture ? "rectangle.dashed.and.camera" : "clipboard")
                Spacer()
                statusLabel
                if permissionCenter.permission(for: kind).isGranted {
                    Text("Allowed").foregroundStyle(.secondary)
                } else {
                    Button("Request") { Task { _ = await permissionCenter.request(kind) } }
                        .frame(minWidth: 84, minHeight: 44)
                        .accessibilityLabel("Request \(kind.title) permission")
                }
                Button("System Settings") { permissionCenter.openSystemSettings(for: kind) }
                    .frame(minHeight: 44)
                    .accessibilityLabel("Open \(kind.title) in System Settings")
            }
            Text(explanation).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var statusLabel: some View {
        let status = permissionCenter.permission(for: kind)
        return Text(status.rawValue == "notDetermined" ? "Not requested" : status.isGranted ? "Ready" : "Denied")
            .font(.callout)
            .foregroundStyle(status.isGranted ? Color.secondary : Color.orange)
            .accessibilityLabel("\(kind.title) status: \(status.rawValue)")
    }
}
