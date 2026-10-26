import AppKit

@MainActor
public final class StatusItemController: NSObject {
    public struct Actions {
        public let openShelf: () -> Void
        public let quickCapture: () -> Void
        public let searchClipboard: () -> Void
        public let audioControls: () -> Void
        public let pauseClipboard: () -> Void
        public let presentationSafe: () -> Void
        public let settings: () -> Void
        public let resetShelfPosition: () -> Void
        public let quit: () -> Void

        public init(openShelf: @escaping () -> Void, quickCapture: @escaping () -> Void, searchClipboard: @escaping () -> Void, audioControls: @escaping () -> Void, pauseClipboard: @escaping () -> Void, presentationSafe: @escaping () -> Void, settings: @escaping () -> Void, resetShelfPosition: @escaping () -> Void, quit: @escaping () -> Void) {
            self.openShelf = openShelf; self.quickCapture = quickCapture; self.searchClipboard = searchClipboard
            self.audioControls = audioControls; self.pauseClipboard = pauseClipboard; self.presentationSafe = presentationSafe
            self.settings = settings; self.resetShelfPosition = resetShelfPosition; self.quit = quit
        }
    }

    private let actions: Actions
    private let item: NSStatusItem

    public init(actions: Actions) {
        self.actions = actions
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Ledge")
        item.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        add("Open Shelf", #selector(openShelf), to: menu)
        add("Quick Capture", #selector(quickCapture), to: menu)
        add("Search Clipboard", #selector(searchClipboard), to: menu)
        add("Audio Controls", #selector(audioControls), to: menu)
        menu.addItem(.separator())
        add("Pause Clipboard", #selector(pauseClipboard), to: menu)
        add("Presentation Safe", #selector(presentationSafe), to: menu)
        menu.addItem(.separator())
        add("Settings…", #selector(openSettings), to: menu)
        add("Reset Shelf Position", #selector(resetShelfPosition), to: menu)
        menu.addItem(.separator())
        add("Quit Ledge", #selector(quit), to: menu)
        return menu
    }

    private func add(_ title: String, _ action: Selector, to menu: NSMenu) { menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self }
    @objc private func openShelf() { actions.openShelf() }
    @objc private func quickCapture() { actions.quickCapture() }
    @objc private func searchClipboard() { actions.searchClipboard() }
    @objc private func audioControls() { actions.audioControls() }
    @objc private func pauseClipboard() { actions.pauseClipboard() }
    @objc private func presentationSafe() { actions.presentationSafe() }
    @objc private func openSettings() { actions.settings() }
    @objc private func resetShelfPosition() { actions.resetShelfPosition() }
    @objc private func quit() { actions.quit() }
}
