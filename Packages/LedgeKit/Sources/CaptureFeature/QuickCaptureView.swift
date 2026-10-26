import SwiftUI

public struct QuickCaptureView: View {
    @Bindable private var store: CaptureStore
    private let beginScreenshot: @MainActor () -> Void
    @State private var text = ""
    @State private var contextText = ""
    @State private var isContextVisible = false
    @State private var errorMessage: String?
    @FocusState private var editorFocused: Bool
    @FocusState private var contextFocused: Bool

    public init(store: CaptureStore, beginScreenshot: @escaping @MainActor () -> Void = {}) { self.store = store; self.beginScreenshot = beginScreenshot }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Capture type", selection: typeBinding) {
                ForEach(CaptureType.allCases) { type in Text(type.rawValue.capitalized).tag(type) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("quick-capture.type")

            TextEditor(text: $text)
                .focused($editorFocused)
                .accessibilityLabel("Capture content")
                .accessibilityIdentifier("quick-capture.editor")
                .frame(minHeight: 72)
                .onChange(of: text) { _, value in store.send(.updateText(value)) }

            if store.state.draft.type == .screenshot {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Choose a screen region after selecting Capture Screenshot. Ledge is hidden while the image is captured and the PNG is stored encrypted on this Mac.", systemImage: "camera.viewfinder")
                        .font(.footnote)
                        .accessibilityIdentifier("quick-capture.screenshot-disclosure")
                    Button("Capture Screenshot", action: beginScreenshot)
                        .accessibilityIdentifier("quick-capture.screenshot")
                }
            }

            if isContextVisible {
                TextField("Context URL (optional)", text: $contextText)
                    .focused($contextFocused)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("quick-capture.context-url")
                    .onSubmit { applyContextURL() }
            }

            contextChips
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("quick-capture.error") }
            HStack {
                Button("Context URL") { revealContextField() }
                    .keyboardShortcut("l", modifiers: .command)
                Spacer()
                Button("Cancel") { store.send(.cancel) }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("quick-capture.save")
            }
        }
        .padding()
        .onAppear { editorFocused = true }
        .onKeyPress(.tab) { changeType(); return .handled }
    }

    @ViewBuilder private var contextChips: some View {
        if let source = store.state.draft.source {
            HStack {
                if let name = source.applicationName { Button("\(name) ×") { store.send(.removeApplicationContext) } }
                if let url = source.explicitURL { Button("\(url.host ?? url.absoluteString) ×") { store.send(.setContextURL(nil)) } }
                Button("Remove all context") { store.send(.removeAllContext) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Capture context")
        }
    }

    private var typeBinding: Binding<CaptureType> {
        Binding(get: { store.state.draft.type }, set: { store.send(.selectType($0)) })
    }
    private func revealContextField() { isContextVisible = true; contextFocused = true }
    private func applyContextURL() {
        switch CaptureContextURL.parse(contextText) {
        case .success(let url): store.send(.setContextURL(url)); errorMessage = nil
        case .failure(let error): errorMessage = String(describing: error)
        }
    }
    private func changeType() {
        let all = CaptureType.allCases
        let index = all.firstIndex(of: store.state.draft.type) ?? 0
        store.send(.selectType(all[(index + 1) % all.count]))
    }
    private func save() {
        Task { @MainActor in
            do { try await store.save(); errorMessage = nil }
            catch { errorMessage = String(describing: error) }
        }
    }
}
