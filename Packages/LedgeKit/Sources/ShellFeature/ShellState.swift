import Foundation

public enum ShelfRoute: String, Sendable, Equatable, CaseIterable {
    case home
    case meeting
    case quickCapture
    case searchClipboard
    case audioControls
    case settings
}

public enum RevealReason: Sendable, Equatable {
    case hover
    case hotKey
    case statusItem
    case userAction
    case recovery
}

public enum DismissReason: Sendable, Equatable {
    case pointerExit
    case actionCompleted
    case escape
    case outsideClick
    case keyWindowLost
    case presentationSafe
    case screenRemoved
    case spaceChanged
}

public enum ExternalInteractionKind: Sendable, Equatable, Hashable {
    case savePanel
    case sharePicker
    case permissionPrompt
}

public struct ExternalInteractionToken: Sendable, Equatable, Hashable {
    public let id: UUID
    public let kind: Kind

    public typealias Kind = ExternalInteractionKind

    public init(id: UUID = UUID(), kind: Kind = .savePanel) {
        self.id = id
        self.kind = kind
    }
}

public enum ShelfPresentation: Sendable, Equatable {
    case hidden
    case peek
    case expanded(ShelfRoute)
    case settings
}

public struct ShellState: Sendable, Equatable {
    public let presentation: ShelfPresentation
    public let screenID: String?
    public let autoHoverSuppressedScreenIDs: Set<String>
    public let externalInteraction: ExternalInteractionToken?

    public init(presentation: ShelfPresentation, screenID: String?, autoHoverSuppressedScreenIDs: Set<String> = [], externalInteraction: ExternalInteractionToken? = nil) {
        self.presentation = presentation
        self.screenID = screenID
        self.autoHoverSuppressedScreenIDs = autoHoverSuppressedScreenIDs
        self.externalInteraction = externalInteraction
    }

    public static func hidden(pendingScreenID: String? = nil) -> ShellState { ShellState(presentation: .hidden, screenID: pendingScreenID) }
    public static func peek(screenID: String) -> ShellState { ShellState(presentation: .peek, screenID: screenID) }
    public static func expanded(route: ShelfRoute, screenID: String) -> ShellState { ShellState(presentation: .expanded(route), screenID: screenID) }
    public static func settings(screenID: String? = nil) -> ShellState { ShellState(presentation: .settings, screenID: screenID) }
}
