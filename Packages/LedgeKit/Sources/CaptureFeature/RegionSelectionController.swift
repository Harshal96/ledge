import CoreGraphics
import Foundation

public struct ScreenshotDisplay: Sendable, Equatable {
    public let id: String
    public let frame: CGRect
    public let backingScale: CGFloat
    public let systemDisplayID: CGDirectDisplayID?

    public init(id: String, frame: CGRect, backingScale: CGFloat, systemDisplayID: CGDirectDisplayID? = nil) {
        self.id = id
        self.frame = frame
        self.backingScale = backingScale
        self.systemDisplayID = systemDisplayID
    }
}

public enum RegionSelectionState: Sendable, Equatable {
    case selecting(screenID: String, rect: CGRect)
    case confirmed(CGRect)
    case canceled
    case rejected(String)
}

public enum RegionSelectionEvent: Sendable, Equatable {
    case escape
    case arrow(Arrow, shift: Bool)
    case returnKey
    public enum Arrow: Sendable, Equatable { case left, right, up, down }
}

public enum RegionSelectionReducer {
    public static let boundaryMessage = "Select an area within one display."

    public static func reduce(_ state: RegionSelectionState, _ event: RegionSelectionEvent, display: ScreenshotDisplay) -> RegionSelectionState {
        guard case let .selecting(screenID, rect) = state else { return state }
        switch event {
        case .escape: return .canceled
        case let .arrow(arrow, shift):
            let distance: CGFloat = shift ? 10 : 1
            let delta: CGPoint
            switch arrow { case .left: delta = CGPoint(x: -distance, y: 0); case .right: delta = CGPoint(x: distance, y: 0); case .up: delta = CGPoint(x: 0, y: distance); case .down: delta = CGPoint(x: 0, y: -distance) }
            let moved = rect.offsetBy(dx: delta.x, dy: delta.y)
            return display.frame.contains(moved) ? .selecting(screenID: screenID, rect: moved) : .selecting(screenID: screenID, rect: rect)
        case .returnKey:
            guard rect.width > 0, rect.height > 0, display.frame.contains(rect) else { return .rejected(boundaryMessage) }
            return .confirmed(rect)
        }
    }
}

@MainActor
public final class RegionSelectionController {
    public private(set) var state: RegionSelectionState
    private let display: ScreenshotDisplay

    public init(display: ScreenshotDisplay, initialRect: CGRect) {
        self.display = display
        self.state = .selecting(screenID: display.id, rect: initialRect)
    }

    public func send(_ event: RegionSelectionEvent) { state = RegionSelectionReducer.reduce(state, event, display: display) }
}
