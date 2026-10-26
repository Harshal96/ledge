import SwiftUI

struct SettingsView: View {
    @StateObject private var permissionCenter: PermissionCenter
    @StateObject private var loginItemController: LoginItemController

    init(
        permissionCenter: PermissionCenter = PermissionCenter(),
        loginItemController: LoginItemController = LoginItemController()
    ) {
        _permissionCenter = StateObject(wrappedValue: permissionCenter)
        _loginItemController = StateObject(wrappedValue: loginItemController)
    }

    var body: some View {
        TabView {
            AutomationSettingsView()
                .tabItem { Label("Automations", systemImage: "bolt.circle") }
                .accessibilityIdentifier("settings.automations")
            GeneralSettingsView(permissionCenter: permissionCenter, loginItemController: loginItemController)
                .tabItem { Label("General", systemImage: "gearshape") }
                .accessibilityIdentifier("settings.general")
            PrivacySettingsView(permissionCenter: permissionCenter)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .accessibilityIdentifier("settings.privacy")
            StorageSettingsView()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
                .accessibilityIdentifier("settings.storage")
            ShortcutSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .accessibilityIdentifier("settings.shortcuts")
            DiagnosticsView(permissionCenter: permissionCenter)
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                .accessibilityIdentifier("settings.diagnostics")
        }
        .frame(minWidth: 620, minHeight: 430)
        .sheet(isPresented: Binding(
            get: { !permissionCenter.onboardingComplete },
            set: { if !$0 { permissionCenter.completeOnboarding() } }
        )) {
            OnboardingView(permissionCenter: permissionCenter)
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var permissionCenter: PermissionCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("A calm shelf for your next action", systemImage: "tray.full")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Ledge stays local and starts without requesting permissions. You can enable each feature when you need it.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Label("Shelf: Command-Option-Space", systemImage: "command")
                Label("Recovery: reopen Ledge or use Command-Option-Space", systemImage: "lifepreserver")
                Label("Private by default: no clipboard or calendar reads until you opt in", systemImage: "lock")
            }
            .font(.callout)
            HStack {
                Spacer()
                Button("Continue") { permissionCenter.completeOnboarding() }
                    .keyboardShortcut(.defaultAction)
                    .frame(minWidth: 110, minHeight: 44)
                    .accessibilityLabel("Continue setup")
            }
        }
        .padding(28)
        .frame(minWidth: 520, minHeight: 300)
        .animation(reduceMotion ? nil : .default, value: permissionCenter.onboardingComplete)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ledge first-run information")
    }
}
