import Testing
import LedgeDomain
@testable import ShellFeature

@Test("Denied calendar does not disable capture or clipboard")
func permissionIsolation() {
    let state = AppCapabilityState(calendar: .denied, screenCapture: .notDetermined, pasteboard: .allowed)

    #expect(state.isEnabled(.meetings) == false)
    #expect(state.isEnabled(.quickCapture) == true)
    #expect(state.isEnabled(.clipboard) == true)
}

@Test("Screen recording is requested only for screenshot capability")
func screenshotCapabilityIsIndependent() {
    let state = AppCapabilityState(calendar: .denied, screenCapture: .notDetermined, pasteboard: .denied)

    #expect(state.isEnabled(.screenshot) == false)
    #expect(state.isEnabled(.quickCapture) == true)
    #expect(state.isEnabled(.clipboard) == false)
}

@Test("Recovery capabilities are available when every gated capability fails")
func recoverySurvivesServiceFailure() {
    let state = AppCapabilityState(calendar: .denied, screenCapture: .denied, pasteboard: .denied)

    #expect(state.isEnabled(.shell))
    #expect(state.isEnabled(.handoff))
    #expect(state.isEnabled(.recovery))
    #expect(state.recoveryAvailable)
}

@Test("Permission presentation is content-free and redacted")
func permissionPresentationRedactsContent() {
    let state = AppCapabilityState(calendar: .authorized, screenCapture: .denied, pasteboard: .allowed)

    #expect(state.permission(for: .meetings) == .authorized)
    #expect(state.permission(for: .screenshot) == .denied)
    #expect(state.diagnosticValues.keys.contains("calendarAuthorized"))
    #expect(state.diagnosticValues.values.allSatisfy { !$0.localizedCaseInsensitiveContains("title") })
}
