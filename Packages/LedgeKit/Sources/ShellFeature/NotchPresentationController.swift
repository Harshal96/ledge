import Foundation

public enum NotchPresentation: Sendable, Equatable {
    case hidden, compact, peek, expanded(String?)
}
public enum NotchEvent: Sendable {
    case pointerEntered, pointerExited, advance, open(String?), dismiss
    case notify(String), activity(String?), suppressAutomatic(Bool), interaction(Bool)
}
public struct NotchSnapshot: Sendable, Equatable {
    public var presentation: NotchPresentation = .hidden
    public var requestsKeyboard = false
    public var summary: String?
    public var deadline: TimeInterval?
}

/// Pure, clock-injected policy. The AppKit coordinator executes its decisions;
/// plugin code never owns windows, focus, timing, or automatic attention policy.
public struct NotchPresentationController: Sendable {
    public private(set) var snapshot = NotchSnapshot()
    private var automaticSuppressed = false
    private var interaction = false
    private var pendingDismiss = false
    private var activity: String?
    private var pending: Pending?
    private enum Pending: Sendable { case open, close }
    public init() {}
    public mutating func send(_ event: NotchEvent, now: TimeInterval) {
        switch event {
        case .pointerEntered:
            guard !automaticSuppressed else { return }
            if case .expanded = snapshot.presentation { snapshot.deadline = nil; pending = nil }
            else { snapshot.deadline = now + 0.2; pending = .open }
        case .pointerExited:
            if !snapshot.requestsKeyboard { snapshot.deadline = now + 0.35; pending = .close }
        case .advance:
            guard let deadline = snapshot.deadline, now + 0.000_001 >= deadline else { return }
            snapshot.deadline = nil
            if pending == .open, !automaticSuppressed { snapshot.presentation = .expanded(nil); snapshot.requestsKeyboard = false }
            else { close() }
            pending = nil
        case let .open(id):
            snapshot.presentation = .expanded(id); snapshot.requestsKeyboard = true; snapshot.deadline = nil; pending = nil
        case .dismiss: close()
        case let .notify(summary):
            guard !automaticSuppressed else { return }
            if case .expanded = snapshot.presentation { return }
            snapshot.summary = summary; snapshot.presentation = .peek; snapshot.requestsKeyboard = false; snapshot.deadline = now + 5; pending = .close
        case let .activity(summary):
            activity = summary
            if snapshot.presentation == .hidden || snapshot.presentation == .compact { snapshot.summary = summary; snapshot.presentation = summary == nil || automaticSuppressed ? .hidden : .compact }
        case let .suppressAutomatic(value):
            automaticSuppressed = value
            if value && !snapshot.requestsKeyboard { close() }
        case let .interaction(value):
            interaction = value
            if !value && pendingDismiss { pendingDismiss = false; close() }
        }
    }
    private mutating func close() {
        if interaction { pendingDismiss = true; return }
        snapshot.presentation = activity == nil || automaticSuppressed ? .hidden : .compact
        snapshot.summary = activity; snapshot.requestsKeyboard = false; snapshot.deadline = nil; pending = nil
    }
}
