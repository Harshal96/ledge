import SwiftUI

@main
struct LedgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView("Ledge Settings", systemImage: "gearshape", description: Text("Settings remain available even when a feature service is unavailable."))
            .frame(minWidth: 360, minHeight: 180)
            .accessibilityIdentifier("settings.recovery")
    }
}
