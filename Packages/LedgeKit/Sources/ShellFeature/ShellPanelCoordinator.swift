import AppKit
import SwiftUI

@MainActor
public protocol ShellPanelControlling: AnyObject {
    func reveal(_ route: ShelfRoute, reason: RevealReason, screenID: String?)
    func dismiss(reason: DismissReason)
    func beginExternalInteraction(_ kind: ExternalInteractionKind) -> ExternalInteractionToken
    func endExternalInteraction(_ token: ExternalInteractionToken)
    func resetPosition()
}

@MainActor
public final class ShellPanelCoordinator: NSObject, ShellPanelControlling {
    private let panel = ShellPanel()
    private let geometry = ShelfGeometryResolver()
    private let screenDescriptor: @MainActor (String?) -> ScreenDescriptor?
    private let contentSize: CGSize
    private var state = ShellState.hidden()
    private var dismissalTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    private var hoverPanel: HoverTriggerPanel?
    private var autoDismiss = false
    public var onHoverReveal: (() -> Void)?
    public private(set) var currentRoute: ShelfRoute = .home

    public init(contentSize: CGSize = CGSize(width: 520, height: 160), screenDescriptor: @escaping @MainActor (String?) -> ScreenDescriptor? = { _ in nil }) {
        self.contentSize = contentSize
        self.screenDescriptor = screenDescriptor
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(panelResignedKey), name: NSWindow.didResignKeyNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    public func installRootView<Content: View>(_ content: Content) {
        panel.contentView = NSHostingView(rootView: content.onHover { [weak self] inside in
            if inside {
                self?.dismissalTask?.cancel()
                if case .peek = self?.state.presentation { self?.onHoverReveal?() }
            }
            else if self?.autoDismiss == true { self?.scheduleExitDismissal() }
        }.onExitCommand { [weak self] in self?.dismiss(reason: .escape) })
    }

    public func startHoverActivation() { rebuildTrigger() }

    @objc private func displaysChanged(_ notification: Notification) { dismiss(reason: .screenRemoved); rebuildTrigger() }
    @objc private func spaceChanged(_ notification: Notification) { dismiss(reason: .spaceChanged) }

    private func rebuildTrigger() {
        hoverPanel?.orderOut(nil)
        guard let screen = screenDescriptor(nil) else { return }
        let placement = NotchGeometryResolver().resolve(screen: screen, expanded: false)
        guard placement.hasNotch else { hoverPanel = nil; return }
        let trigger = HoverTriggerPanel(frame: placement.trigger, onEnter: { [weak self] in
            self?.hoverTask?.cancel()
            self?.hoverTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.onHoverReveal?()
            }
        }, onExit: { [weak self] in self?.hoverTask?.cancel() })
        hoverPanel = trigger; trigger.orderFrontRegardless()
    }

    public func reveal(_ route: ShelfRoute, reason: RevealReason, screenID: String?) {
        dismissalTask?.cancel()
        guard let screen = screenDescriptor(screenID) else { return }
        currentRoute = route
        autoDismiss = reason == .hover
        panel.collectionBehavior = reason == .hover ? [.moveToActiveSpace, .transient, .ignoresCycle] : [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        state = .expanded(route: route, screenID: screen.id)
        place(on: screen)
        panel.orderFrontRegardless()
        if reason != .hover { panel.makeKey() }
    }

    public func showPeek(on screen: ScreenDescriptor, contentSize: CGSize) {
        guard !state.autoHoverSuppressedScreenIDs.contains(screen.id) else { return }
        state = .peek(screenID: screen.id)
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
        panel.setFrame(NotchGeometryResolver().resolve(screen: screen, expanded: false).frame, display: true)
        panel.orderFrontRegardless()
        schedulePeekDismissal()
    }

    public func dismiss(reason: DismissReason) {
        dismissalTask?.cancel()
        guard state.externalInteraction == nil else { return }
        panel.orderOut(nil)
        state = .hidden(pendingScreenID: state.screenID)
    }

    public func beginExternalInteraction(_ kind: ExternalInteractionKind) -> ExternalInteractionToken {
        let token = ExternalInteractionToken(kind: kind)
        state = ShellReducer.reduce(state, .externalInteractionBegan(token))
        return token
    }
    public func endExternalInteraction(_ token: ExternalInteractionToken) { state = ShellReducer.reduce(state, .externalInteractionEnded(token)) }
    public func resetPosition() { state = .hidden(pendingScreenID: state.screenID); panel.setFrameOrigin(.zero) }

    @objc private func panelResignedKey(_ notification: Notification) { dismiss(reason: .keyWindowLost) }

    private func place(on screen: ScreenDescriptor, contentSize: CGSize? = nil) {
        let placement = NotchGeometryResolver().resolve(screen: screen, expanded: true, height: currentRoute == .home ? 420 : 380)
        panel.setFrame(placement.frame, display: true)
    }

    private func scheduleExitDismissal() {
        dismissalTask?.cancel()
        dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.dismiss(reason: .pointerExit)
        }
    }

    private func schedulePeekDismissal() {
        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.dismiss(reason: .pointerExit)
        }
    }
}
