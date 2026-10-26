import Foundation

public enum ShellEvent: Sendable, Equatable {
    case hoverDwelled(screenID: String)
    case pointerExited
    case hotKeyToggled(screenID: String)
    case expand(ShelfRoute)
    case actionCompleted
    case escapePressed
    case outsideClick
    case fullScreenChanged(screenID: String, isLikelyOrUnknown: Bool)
    case presentationSafeChanged(Bool)
    case screensChanged(availableIDs: Set<String>, fallbackID: String?)
    case spaceChanged(screenID: String)
    case externalInteractionBegan(ExternalInteractionToken)
    case externalInteractionEnded(ExternalInteractionToken)
    case externalInteractionTimedOut(ExternalInteractionToken)
}

public enum ShellReducer {
    public static func reduce(_ state: ShellState, _ event: ShellEvent) -> ShellState {
        switch event {
        case let .hoverDwelled(screenID) where !state.autoHoverSuppressedScreenIDs.contains(screenID):
            return .peek(screenID: screenID)
        case .hoverDwelled:
            return state
        case .pointerExited, .actionCompleted, .escapePressed:
            return state.externalInteraction == nil ? .hidden(pendingScreenID: state.screenID) : state
        case let .hotKeyToggled(screenID):
            return state.presentation == .hidden ? .peek(screenID: screenID) : .hidden(pendingScreenID: screenID)
        case let .expand(route):
            guard let screenID = state.screenID else { return state }
            return .expanded(route: route, screenID: screenID)
        case .outsideClick:
            return state.externalInteraction == nil ? .hidden(pendingScreenID: state.screenID) : state
        case let .fullScreenChanged(screenID, isLikelyOrUnknown):
            var suppression = state.autoHoverSuppressedScreenIDs
            if isLikelyOrUnknown { suppression.insert(screenID) } else { suppression.remove(screenID) }
            let next = ShellState(presentation: state.presentation, screenID: state.screenID, autoHoverSuppressedScreenIDs: suppression, externalInteraction: state.externalInteraction)
            return isLikelyOrUnknown && state.screenID == screenID && state.presentation == .peek ? .hidden(pendingScreenID: screenID) : next
        case let .presentationSafeChanged(enabled):
            return enabled ? .hidden(pendingScreenID: state.screenID) : state
        case let .screensChanged(availableIDs, fallbackID):
            guard let screenID = state.screenID, !availableIDs.contains(screenID) else { return state }
            return .hidden(pendingScreenID: fallbackID)
        case let .spaceChanged(screenID):
            return state.presentation == .peek ? .hidden(pendingScreenID: screenID) : state
        case let .externalInteractionBegan(token):
            return ShellState(presentation: state.presentation, screenID: state.screenID, autoHoverSuppressedScreenIDs: state.autoHoverSuppressedScreenIDs, externalInteraction: token)
        case let .externalInteractionEnded(token), let .externalInteractionTimedOut(token):
            guard state.externalInteraction == token else { return state }
            return ShellState(presentation: state.presentation, screenID: state.screenID, autoHoverSuppressedScreenIDs: state.autoHoverSuppressedScreenIDs)
        }
    }
}
