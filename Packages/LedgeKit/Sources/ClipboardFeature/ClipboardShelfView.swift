#if canImport(SwiftUI)
import SwiftUI

public struct ClipboardShelfView: View {
    @Bindable private var store: ClipboardStore
    private let copySelection: @Sendable (ClipboardValue) async -> Void
    @State private var query = ""; @State private var results: [ClipboardSnapshot] = []; @State private var selection: ClipboardSnapshot?; @State private var showingClearConfirmation = false
    public init(store: ClipboardStore, copySelection: @escaping @Sendable (ClipboardValue) async -> Void = { _ in }) { self.store = store; self.copySelection = copySelection }
    public var body: some View {
        VStack(alignment: .leading) {
            TextField("Search Clipboard", text: $query).accessibilityLabel("Search Clipboard")
            List(results, selection: $selection) { entry in Text(entry.displayText).lineLimit(2).tag(entry) }
            HStack { Button("Search") {}.keyboardShortcut("f", modifiers: .command); Button("Copy Selected") { if let selection { Task { await copySelection(selection.value) } } }.keyboardShortcut(.return, modifiers: []); Button("Pause") {}.keyboardShortcut(.escape); Button("Favorite") { if let selection { Task { await store.setFavorite(selection, isFavorite: !selection.isFavorite); results = await store.results(matching: query) } } }.keyboardShortcut("f", modifiers: [.command, .shift]); Button("Delete") { if let selection { Task { await store.delete(selection); results = await store.results(matching: query) } } }.keyboardShortcut(.delete, modifiers: []); Button("Clear All") { showingClearConfirmation = true } }
        }.confirmationDialog("Clear all clipboard history?", isPresented: $showingClearConfirmation) { Button("Clear All", role: .destructive) { Task { await store.clearAll(); results = [] } } }.task { await store.reload(); results = await store.results(matching: query) }.task(id: query) { results = await store.results(matching: query) }
    }
}
#endif
