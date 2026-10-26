#if LEDGE_UITESTING
import SwiftUI

@MainActor
final class UITestDiagnostics: ObservableObject {
    @Published var screen = ""
    @Published var hotKeyResult = ""
    @Published var action = "none"
    @Published var presentationSafe = "disabled"
    @Published var shelfPresentation = "hidden"
    @Published var statusMenu = "unavailable"
    @Published var settings = "closed"
    @Published var screenGeometry = "unavailable"
    @Published var audioFixture = "unavailable"
    @Published var audioInputMute = "unsupported"
}

struct UITestDiagnosticsView: View {
    @ObservedObject var diagnostics: UITestDiagnostics

    var body: some View {
        VStack(alignment: .leading) {
            signal("ui.fixture.screen", diagnostics.screen)
            signal("ui.hotkey.result", diagnostics.hotKeyResult)
            signal("ui.fixture.action", diagnostics.action)
            signal("ui.presentation-safe", diagnostics.presentationSafe)
            signal("ui.shell.presentation", diagnostics.shelfPresentation)
            signal("ui.recovery.status-menu", diagnostics.statusMenu)
            signal("ui.recovery.settings", diagnostics.settings)
            signal("ui.fixture.geometry", diagnostics.screenGeometry)
            signal("ui.audio.fixture", diagnostics.audioFixture)
            signal("ui.audio.input-mute", diagnostics.audioInputMute)
        }
        .padding()
    }

    private func signal(_ identifier: String, _ value: String) -> some View {
        Text(value).accessibilityIdentifier(identifier)
    }
}
#endif
