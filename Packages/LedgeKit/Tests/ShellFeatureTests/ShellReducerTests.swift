import Testing
@testable import ShellFeature

@Test("Disconnected display falls back without stale geometry")
func disconnectedDisplayFallback() {
    let state = ShellReducer.reduce(
        .expanded(route: .meeting, screenID: "removed"),
        .screensChanged(availableIDs: ["main"], fallbackID: "main")
    )
    #expect(state == .hidden(pendingScreenID: "main"))
}

@Test("External interaction lease blocks outside dismissal until it is released")
func externalInteractionLeaseProtectsShelf() {
    let token = ExternalInteractionToken()
    let initial = ShellState.expanded(route: .quickCapture, screenID: "main")
    let leased = ShellReducer.reduce(initial, .externalInteractionBegan(token))

    #expect(ShellReducer.reduce(leased, .outsideClick) == leased)
    #expect(ShellReducer.reduce(leased, .externalInteractionEnded(token)) == initial)
    #expect(ShellReducer.reduce(leased, .outsideClick) == leased)
}

@Test("Unknown full screen suppresses automatic hover but not an explicit hotkey")
func fullScreenSuppressionKeepsHotkeyAvailable() {
    let suppressed = ShellReducer.reduce(
        .hidden(pendingScreenID: "main"),
        .fullScreenChanged(screenID: "main", isLikelyOrUnknown: true)
    )

    #expect(ShellReducer.reduce(suppressed, .hoverDwelled(screenID: "main")) == suppressed)
    #expect(ShellReducer.reduce(suppressed, .hotKeyToggled(screenID: "main")) == .peek(screenID: "main"))
}

@Test("External-interaction kinds create distinct typed leases")
func externalInteractionKindsAreTyped() {
    let save = ExternalInteractionToken(kind: .savePanel)
    let permission = ExternalInteractionToken(kind: .permissionPrompt)

    #expect(save.kind == .savePanel)
    #expect(permission.kind == .permissionPrompt)
    #expect(save != permission)
}

@MainActor
@Test("Hotkey router delivers only configured registration IDs")
func hotKeyRouterDeliversConfiguredChords() {
    let first = HotKeyChord(keyCode: 12, modifiers: 1 << 8)
    let second = HotKeyChord(keyCode: 14, modifiers: 1 << 8)
    let router = HotKeyEventRouter(chords: [first, second])

    #expect(router.chord(forRegistrationID: 1) == first)
    #expect(router.chord(forRegistrationID: 2) == second)
    #expect(router.chord(forRegistrationID: 3) == nil)

    let sink = RecordingHotKeySink()
    router.deliver(registrationID: 2, to: sink)
    router.deliver(registrationID: 3, to: sink)
    #expect(sink.delivered == [second])
}

@MainActor
private final class RecordingHotKeySink: HotKeyEventSink {
    var delivered: [HotKeyChord] = []
    func deliver(_ chord: HotKeyChord) { delivered.append(chord) }
}
