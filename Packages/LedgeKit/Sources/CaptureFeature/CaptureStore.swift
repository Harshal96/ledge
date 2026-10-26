import Foundation
import Observation
import LedgeDomain

@MainActor @Observable
public final class CaptureStore {
    public enum Presentation: Sendable, Equatable { case editing, dismissed }
    public struct State: Sendable, Equatable {
        public let draft: CaptureDraft
        public let presentation: Presentation
        public static func initial(source: SourceContext? = nil) -> State { State(draft: CaptureDraft(type: .note, text: "", source: source), presentation: .editing) }
    }
    public enum Action: Sendable { case updateText(String), selectType(CaptureType), setContextURL(CaptureContextURL?), removeApplicationContext, removeAllContext, cancel }
    public private(set) var state: State
    private let service: QuickCaptureService

    public init(service: QuickCaptureService, initial: State = .initial()) { self.service = service; self.state = initial }
    public func reset() { state = .initial() }
    public static func reduce(_ state: State, _ action: Action) -> State {
        switch action {
        case .updateText(let text): return State(draft: CaptureDraft(type: state.draft.type, text: text, source: state.draft.source, allowsFrozenSourceAttachment: state.draft.allowsFrozenSourceAttachment), presentation: state.presentation)
        case .selectType(let type): return State(draft: CaptureDraft(type: type, text: state.draft.text, source: state.draft.source, allowsFrozenSourceAttachment: state.draft.allowsFrozenSourceAttachment), presentation: state.presentation)
        case .setContextURL(let url): return State(draft: state.draft.withContextURL(url), presentation: state.presentation)
        case .removeApplicationContext: return State(draft: state.draft.removingApplicationContext(), presentation: state.presentation)
        case .removeAllContext: return State(draft: state.draft.removingAllContext(), presentation: state.presentation)
        case .cancel: return State(draft: state.draft, presentation: .dismissed)
        }
    }
    public func send(_ action: Action) { state = Self.reduce(state, action); if case .cancel = action { service.cancel() } }
    public func save(now: Date = .now) async throws { _ = try await service.save(state.draft, now: now); state = State(draft: state.draft, presentation: .dismissed) }
}
