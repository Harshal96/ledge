import AppKit

@MainActor
public final class HoverTriggerPanel: NSPanel {
    private let onEnter: @MainActor () -> Void
    private let onExit: @MainActor () -> Void
    private var trackingArea: NSTrackingArea?

    public init(frame: CGRect, onEnter: @escaping @MainActor () -> Void, onExit: @escaping @MainActor () -> Void) {
        self.onEnter = onEnter
        self.onExit = onExit
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        contentView = view
        let area = NSTrackingArea(rect: view.bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        view.addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) { onEnter() }
    public override func mouseExited(with event: NSEvent) { onExit() }
}
