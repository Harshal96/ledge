import AppKit
import Foundation
import SwiftUI

struct DiagnosticsReport: Codable, Equatable, Sendable {
    let appVersion: String
    let osVersion: String
    let capabilities: [String: String]
    let counts: [String: Int]
    let timingsMilliseconds: [String: Int]
    let errorCategories: [String]

    static func make(capabilities: [String: String]) -> DiagnosticsReport {
        DiagnosticsReport(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            capabilities: capabilities,
            counts: ["clipboardItems": 0, "meetings": 0, "vaultItems": 0],
            timingsMilliseconds: [:],
            errorCategories: []
        )
    }

    var jsonData: Data? {
        try? JSONEncoder().encode(self)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var permissionCenter: PermissionCenter
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Local diagnostics") {
                LabeledContent("App version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
                LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                Text("Reports include capability booleans, counts, timings, and error categories only. Clipboard text, calendar titles, URLs, paths, bundle IDs, and payloads are never exported.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Export Diagnostics") { export() }
                    .frame(minHeight: 44)
                    .keyboardShortcut("e", modifiers: [.command, .option])
                if let statusMessage { Text(statusMessage).foregroundStyle(.secondary) }
            }
            Section("Capability status") {
                ForEach(permissionCenter.capabilities.diagnosticValues.keys.sorted(), id: \.self) { key in
                    LabeledContent(key, value: permissionCenter.capabilities.diagnosticValues[key] ?? "false")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ledge-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard let data = DiagnosticsReport.make(capabilities: permissionCenter.capabilities.diagnosticValues).jsonData else {
            statusMessage = "Diagnostics could not be encoded."
            return
        }
        do {
            try data.write(to: destination, options: .atomic)
            statusMessage = "Diagnostics exported locally."
        } catch {
            statusMessage = "Diagnostics export failed."
        }
    }
}
