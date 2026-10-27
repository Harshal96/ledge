import AppKit
import SwiftUI
import ShellFeature
import PluginUI

/// Infrastructure only: optional apps are owned by the registry, not this app.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let notch = NotchWindowCoordinator()
    private var libraryWindow: NSWindow?
    private var displayPreference: String?
    private var presentationSafe = false
    private var defaultsObserver: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = AppLibraryStore.shared
        notch.installRootView(PluginNotchView(store: store, openLibrary: { [weak self] in self?.openLibrary() }, dismiss: { [weak self] in self?.notch.dismiss() }))
        notch.onExplicitOpen = { Task { await store.refresh() } }
        store.onInteraction = { [weak self] active in self?.notch.setInteraction(active) }
        store.onPeek = { [weak self] summary in self?.notch.notify(summary) ?? false }
        refreshShellPreferences()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshShellPreferences() } }
        openLibrary()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openLibrary(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            var stopped = await AppLibraryStore.shared.stopForQuit()
            while !stopped {
                let alert = NSAlert(); alert.messageText = "Could not confirm automations stopped"; alert.informativeText = "The runner is unavailable. Retry, keep Ledge open, or explicitly quit anyway; background work may continue if you quit without confirmation."; alert.addButton(withTitle: "Retry stop"); alert.addButton(withTitle: "Keep Ledge open"); alert.addButton(withTitle: "Quit anyway")
                switch alert.runModal() {
                case .alertFirstButtonReturn: stopped = await AppLibraryStore.shared.stopForQuit()
                case .alertSecondButtonReturn: sender.reply(toApplicationShouldTerminate: false); return
                default: stopped = true
                }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }; return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) } }
    private func refreshShellPreferences() {
        let selectedDisplay = UserDefaults.standard.string(forKey: "ledge.shell.displayID")
        let safe = UserDefaults.standard.bool(forKey: "ledge.presentationSafe")
        if selectedDisplay != displayPreference || safe != presentationSafe {
            displayPreference = selectedDisplay; presentationSafe = safe; notch.preferencesChanged()
        }
    }
    private func openLibrary() {
        notch.dismiss()
        if libraryWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 880, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Ledge — Apps Library"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AppLibraryView()); window.center(); libraryWindow = window
        }
        libraryWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
