import SwiftUI
import AutomationDomain

public struct PluginViewRenderer: View {
    let presentation: PluginPresentation
    let dispatch: (String, JSONValue) -> Void
    public init(presentation: PluginPresentation, dispatch: @escaping (String, JSONValue) -> Void) { self.presentation = presentation; self.dispatch = dispatch }
    public var body: some View { node(presentation.root) }
    private func node(_ value: PluginViewNode) -> AnyView {
        switch value.kind {
        case "section", "form", "list":
            return AnyView(VStack(alignment: .leading, spacing: 10) {
                if let text = value.text { Text(text).font(.headline) }
                ForEach(value.children ?? []) { node($0) }
            }.frame(maxWidth: .infinity, alignment: .leading))
        case "row": return AnyView(HStack { ForEach(value.children ?? []) { node($0) } })
        case "badge": return AnyView(Text(value.text ?? "").font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4).background(.white.opacity(0.1), in: Capsule()))
        case "progress": return AnyView(ProgressView(value.text ?? "", value: value.value?.number ?? 0))
        case "button": return AnyView(Button(value.text ?? "Run") { if let command = value.command { dispatch(command, value.arguments ?? .empty) } }.buttonStyle(.bordered).disabled(value.command == nil).accessibilityIdentifier("plugin.action.\(value.id)"))
        case "toggle": return AnyView(Toggle(value.text ?? "", isOn: Binding(get: { value.value?.bool ?? false }, set: { newValue in if let command = value.command { dispatch(command, .object(["value": .bool(newValue)])) } })).disabled(value.command == nil))
        case "selection":
            return AnyView(Menu(value.text ?? "Choose") {
                ForEach(value.value?.array?.compactMap(\.string) ?? [], id: \.self) { option in
                    Button(option) { if let command = value.command { dispatch(command, .object(["value": .string(option)])) } }
                }
            }.disabled(value.command == nil))
        case "image": return AnyView(Label("Asset preview unavailable", systemImage: "photo").foregroundStyle(.secondary))
        default:
            // Treat markdown as data. No raw HTML, link-triggered actions, remote
            // images or arbitrary filesystem paths are loaded by the renderer.
            return AnyView(Text(value.text ?? "").font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading))
        }
    }
}

public struct PluginFormRenderer: View {
    let schema: JSONValue
    @Binding var draft: JSONValue
    public init(schema: JSONValue, draft: Binding<JSONValue>) { self.schema = schema; self._draft = draft }
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach((schema["properties"].object ?? [:]).keys.sorted(), id: \.self) { key in
                field(key, rule: schema["properties"][key])
            }
        }
    }
    private func binding(_ key: String) -> Binding<JSONValue> {
        Binding(get: { draft.object?[key] ?? schema["properties"][key]["default"] }, set: { value in var object = draft.object ?? [:]; object[key] = value; draft = .object(object) })
    }
    private func field(_ key: String, rule: JSONValue) -> AnyView {
        let value = binding(key)
        let label = rule["title"].string ?? key
        let editor: AnyView
        if let choices = rule["enum"].array?.compactMap(\.string) {
            editor = AnyView(Picker(label, selection: Binding(get: { value.wrappedValue.string ?? choices.first ?? "" }, set: { value.wrappedValue = .string($0) })) { ForEach(choices, id: \.self) { Text($0).tag($0) } })
        } else {
            switch rule["type"].string {
            case "boolean": editor = AnyView(Toggle(label, isOn: Binding(get: { value.wrappedValue.bool ?? false }, set: { value.wrappedValue = .bool($0) })))
            case "array": editor = AnyView(VStack(alignment: .leading) { Text(label).font(.callout.weight(.medium)); TextEditor(text: Binding(get: { value.wrappedValue.array?.compactMap(\.string).joined(separator: "\n") ?? "" }, set: { value.wrappedValue = .array($0.split(separator: "\n").map { .string(String($0).trimmingCharacters(in: .whitespaces)) }) })).font(.system(.body, design: .monospaced)).frame(height: 70).border(.quaternary).accessibilityLabel(label); Text("One value per line").font(.caption).foregroundStyle(.secondary) })
            case "integer", "number": editor = AnyView(TextField(label, text: Binding(get: { value.wrappedValue.number.map { String(format: "%g", $0) } ?? value.wrappedValue.string ?? "" }, set: { value.wrappedValue = Double($0).map(JSONValue.number) ?? .string($0) })))
            case "object": editor = AnyView(GroupBox(label) { PluginFormRenderer(schema: rule, draft: value) })
            default: editor = AnyView(TextField(label, text: Binding(get: { value.wrappedValue.string ?? "" }, set: { value.wrappedValue = .string($0) })))
            }
        }
        return AnyView(VStack(alignment: .leading, spacing: 4) { editor; if let description = rule["description"].string { Text(description).font(.caption).foregroundStyle(.secondary) } })
    }
}
