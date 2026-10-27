import AppKit
import SwiftUI

@MainActor public final class NotchWindowCoordinator: NSObject {
    private let panel = ShellPanel()
    private var trigger: HoverTriggerPanel?
    private var policy = NotchPresentationController()
    private var deadlineTask: Task<Void, Never>?
    private var root = AnyView(EmptyView())
    private var expanded = false
    private var previousApp: NSRunningApplication?
    private var explicitScreenID: String?
    public var onExplicitOpen: (() -> Void)?
    public override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resignedKey), name: NSWindow.didResignKeyNotification, object: panel)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    public func installRootView<V: View>(_ view: V) { root = AnyView(view); rebuildTrigger() }
    public func open(instanceID: String? = nil) {
        let chosen = NotchDisplaySelection.select(NSScreen.screens.map(descriptor), preference: UserDefaults.standard.string(forKey: "ledge.shell.displayID"), pointer: NSEvent.mouseLocation)
        explicitScreenID = chosen?.id
        let app = NSWorkspace.shared.frontmostApplication
        if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = app }
        send(.open(instanceID)); onExplicitOpen?()
    }
    public func dismiss() { send(.dismiss) }
    @discardableResult public func notify(_ summary: String) -> Bool { refreshPolicy(); send(.notify(summary)); return policy.snapshot.presentation == .peek }
    public func setInteraction(_ active: Bool) { send(.interaction(active)) }
    public func resetPosition() { UserDefaults.standard.removeObject(forKey: "ledge.shell.displayID"); preferencesChanged() }
    public func preferencesChanged() { explicitScreenID = nil; dismiss(); rebuildTrigger(); refreshPolicy() }
    @objc private func resignedKey() { dismiss() }
    @objc private func displaysChanged() { rebuildTrigger(); render() }
    @objc private func spaceChanged() { refreshPolicy(); rebuildTrigger() }
    private func screen() -> NSScreen? {
        let preference = explicitScreenID ?? UserDefaults.standard.string(forKey: "ledge.shell.displayID")
        let chosen = NotchDisplaySelection.select(NSScreen.screens.map(descriptor), preference: preference, pointer: nil)
        return NSScreen.screens.first(where: { Self.id($0) == chosen?.id })
    }
    private static func id(_ screen: NSScreen) -> String { String((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) }
    private func descriptor(_ screen: NSScreen) -> ScreenDescriptor {
        let i = screen.safeAreaInsets
        return .init(id: Self.id(screen), frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaInsets: .init(top: i.top, left: i.left, bottom: i.bottom, right: i.right), auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea, auxiliaryTopRightArea: screen.auxiliaryTopRightArea, isBuiltIn: i.top > 0)
    }
    private func automaticAllowed() -> Bool {
        if UserDefaults.standard.bool(forKey: "ledge.presentationSafe") { return false }
        guard let screen = screen(), let front = NSWorkspace.shared.frontmostApplication,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let visible = windows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == front.processIdentifier && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 }
        guard !visible.isEmpty else { return front.processIdentifier == ProcessInfo.processInfo.processIdentifier }
        for item in visible {
            if let value = item[kCGWindowBounds as String] as? [String: Any], let rect = CGRect(dictionaryRepresentation: value as CFDictionary), rect.width >= screen.frame.width - 2, rect.height >= screen.frame.height - 2 { return false }
        }
        return true
    }
    private func refreshPolicy() { send(.suppressAutomatic(!automaticAllowed())) }
    private func rebuildTrigger() {
        trigger?.orderOut(nil); trigger = nil
        guard let screen = screen(), automaticAllowed() else { return }
        let placement = NotchGeometryResolver().resolve(screen: descriptor(screen), expanded: false)
        trigger = HoverTriggerPanel(frame: placement.trigger, onEnter: { [weak self] in self?.send(.pointerEntered) }, onExit: { [weak self] in self?.send(.pointerExited) })
        trigger?.orderFrontRegardless()
    }
    private func send(_ event: NotchEvent) {
        policy.send(event, now: ProcessInfo.processInfo.systemUptime); render(); deadlineTask?.cancel()
        if let deadline = policy.snapshot.deadline {
            let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            deadlineTask = Task { [weak self] in do { try await Task.sleep(for: .seconds(delay)) } catch { return }; self?.send(.advance) }
        }
    }
    private func render() {
        guard let screen = screen() else { panel.orderOut(nil); return }
        let state = policy.snapshot
        if state.presentation == .hidden {
            let hadKeyboard = panel.isKeyWindow; panel.orderOut(nil); expanded = false
            if hadKeyboard { previousApp?.activate(options: []) }; previousApp = nil; explicitScreenID = nil; return
        }
        let expand: Bool
        if case .expanded = state.presentation { expand = true } else { expand = false }
        if !panel.isVisible || expand != expanded {
            let content = expand ? root : AnyView(Text(state.summary ?? "Ledge").font(.callout.weight(.medium)).padding(.horizontal, 16).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18)))
            panel.contentView = NSHostingView(rootView: content.onHover { [weak self] inside in self?.send(inside ? .pointerEntered : .pointerExited) }.onExitCommand { [weak self] in self?.dismiss() }.simultaneousGesture(TapGesture().onEnded { [weak self] in if self?.panel.isKeyWindow != true { self?.open() } }))
        }
        expanded = expand
        panel.collectionBehavior = state.requestsKeyboard ? [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle] : [.moveToActiveSpace, .transient, .ignoresCycle]
        let frame = NotchGeometryResolver().resolve(screen: descriptor(screen), expanded: expand).frame
        if !panel.isVisible { panel.setFrame(CGRect(x: frame.minX, y: frame.maxY - 2, width: frame.width, height: 2), display: false); panel.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { context in context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22; panel.animator().setFrame(frame, display: true) }
        if state.requestsKeyboard { panel.makeKey() }
    }
}
