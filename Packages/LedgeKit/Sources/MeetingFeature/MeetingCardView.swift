#if canImport(SwiftUI)
import SwiftUI

public struct MeetingCardView: View {
    @Bindable private var store: MeetingStore
    private let open: @Sendable (URL) async -> Void
    public init(store: MeetingStore, open: @escaping @Sendable (URL) async -> Void = { _ in }) { self.store = store; self.open = open }
    public var body: some View {
        let state = store.state()
        VStack(alignment: .leading, spacing: 8) {
            if let title = state.title { Text(title).font(.headline).accessibilityLabel("Meeting title: \(title)") }
            if let countdown = state.countdown { Text("Starts in \(countdown)").accessibilityLabel("Meeting starts in \(countdown)") }
            if let agenda = state.agenda { Text(agenda).lineLimit(4).accessibilityLabel("Agenda preview") }
            if state.showsJoin { Button("Join") { if let url = store.beginJoin() { Task { await open(url) } } }.keyboardShortcut(.return, modifiers: []).frame(minWidth: 44, minHeight: 44).accessibilityHint("Join the upcoming meeting") }
            if let host = store.confirmationHost { Button("Join \(host)") { if let url = store.confirmJoin() { Task { await open(url) } } }.frame(minWidth: 44, minHeight: 44).accessibilityHint("Confirm opening \(host)") }
        }.onAppear { store.setVisible(true) }.onDisappear { store.setVisible(false) }
    }
}
#endif
