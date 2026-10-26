import AppKit
import AutomationDomain
import AudioFeature
import Carbon.HIToolbox
import CaptureFeature
import ClipboardFeature
import LedgeDomain
import LedgeStorage
import MeetingFeature
import ShellFeature
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var panelCoordinator = ShellPanelCoordinator(screenDescriptor: { [weak self] screenID in self?.resolvedScreenDescriptor(screenID) })
    private lazy var appCoordinator = AppCoordinator(environment: .live, panel: panelCoordinator)
    private var quickCaptureService: QuickCaptureService?
    private var captureStore: CaptureStore?
    private var audioHardware: AudioHardwareService?
    private var audioSnapshot: AudioSnapshot = .empty
    private var clipboardStore: ClipboardStore?
    private var clipboardMonitor: ClipboardMonitor?
    private var clipboardTask: Task<Void, Never>?
    private var clipboardPaused = false
    private var meetingStore: MeetingStore?
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?
    private let hotKeys = CarbonHotKeyRegistrar()
    private let shelfChord = HotKeyChord(keyCode: 49, modifiers: UInt32(cmdKey | optionKey))
    private let captureChord = HotKeyChord(keyCode: 9, modifiers: UInt32(cmdKey | optionKey))
    #if LEDGE_UITESTING
    private let diagnostics = UITestDiagnostics()
    private var diagnosticsPanel: NSPanel?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboardPaused = UserDefaults.standard.bool(forKey: "ledge.clipboard.paused")
        if UserDefaults.standard.bool(forKey: "ledge.recovery.menuIcon") { createStatusItem() }
        configureFeatureServices()
        configureCoordinator()
        panelCoordinator.onHoverReveal = { [weak self] in
            guard let self else { return }
            self.installShelfView(self.appCoordinator.resolution, route: .home)
            self.panelCoordinator.reveal(.home, reason: .hover, screenID: nil)
        }
        panelCoordinator.startHoverActivation()
        AutomationAppStore.shared.onPeek = { [weak self] summary in
            guard let self, self.panelCoordinator.currentRoute == .home, let screen = self.resolvedScreenDescriptor(nil) else { return }
            self.panelCoordinator.installRootView(HStack(spacing: 10) { Image(systemName: "bolt.circle.fill").foregroundStyle(.cyan); Text(summary).font(.callout.weight(.semibold)); Spacer(); Text("Ledge").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal, 18).frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.white).background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)))
            self.panelCoordinator.showPeek(on: screen, contentSize: CGSize(width: 250, height: 56))
        }
        AutomationAppStore.shared.start()
        #if LEDGE_UITESTING
        applyUITestFixture()
        Task { await appCoordinator.start() }
        showUITestDiagnostics()
        #else
        registerHotkeys()
        Task { await appCoordinator.start() }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.unregisterAll()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { await AutomationAppStore.shared.stopForQuit(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openShelf()
        return true
    }

    private func configureCoordinator() {
        appCoordinator.onResolutionChanged = { [weak self] resolution in
            guard self?.panelCoordinator.currentRoute == .home else { return }
            self?.installShelfView(resolution, route: .home)
        }
        appCoordinator.onRouteRequested = { [weak self] route in
            guard let self else { return }
            self.installShelfView(self.appCoordinator.resolution, route: route)
            if route == .audioControls { self.refreshAudio() }
            if route == .meeting { self.requestMeetingAccess() }
            if route == .searchClipboard { self.startClipboardMonitoringIfEnabled() }
        }
        installShelfView(appCoordinator.resolution, route: .home)
    }

    private func installShelfView(_ resolution: ActionResolution, route: ShelfRoute) {
        if route == .home {
            panelCoordinator.installRootView(AutomationNotchView(store: AutomationAppStore.shared, capture: { [weak self] in self?.beginQuickCapture() }, settings: { [weak self] in self?.openSettings() }, dismiss: { [weak self] in self?.panelCoordinator.dismiss(reason: .escape) }))
            return
        }
        if route == .quickCapture, let captureStore {
            panelCoordinator.installRootView(QuickCaptureView(store: captureStore))
            return
        }
        if route == .audioControls {
            panelCoordinator.installRootView(AudioCardView(
                snapshot: audioSnapshot,
                setOutputVolume: { [weak self] value in self?.setOutputVolume(value) },
                toggleOutputMute: { [weak self] muted in self?.setOutputMuted(muted) },
                toggleInputMute: { [weak self] muted in self?.setInputMuted(muted) }
            ))
            return
        }
        if route == .searchClipboard, let clipboardStore {
            panelCoordinator.installRootView(ClipboardShelfView(store: clipboardStore))
            return
        }
        if route == .meeting, let meetingStore {
            panelCoordinator.installRootView(MeetingCardView(store: meetingStore, open: { url in
                await MainActor.run { _ = NSWorkspace.shared.open(url) }
            }))
            return
        }
        panelCoordinator.installRootView(ShelfRootView(
            route: route,
            actions: resolution,
            dismiss: { [weak self] in self?.appCoordinator.dismissCurrentAction() },
            expand: { [weak self] in
                guard let candidate = self?.appCoordinator.resolution.primary else { return }
                self?.appCoordinator.dispatch(candidate)
            },
            performAction: { [weak self] candidate in self?.appCoordinator.dispatch(candidate) }
        ))
    }

    private func createStatusItem() {
        statusItem = StatusItemController(actions: .init(
            openShelf: { [weak self] in self?.openShelf() },
            quickCapture: { [weak self] in self?.beginQuickCapture() },
            searchClipboard: { [weak self] in self?.openSearchClipboard() },
            audioControls: { [weak self] in self?.openAudioControls() },
            pauseClipboard: { [weak self] in self?.toggleClipboardPause() },
            presentationSafe: { [weak self] in self?.panelCoordinator.dismiss(reason: .presentationSafe) },
            settings: { [weak self] in self?.openSettings() },
            resetShelfPosition: { [weak self] in self?.panelCoordinator.resetPosition() },
            quit: { NSApp.terminate(nil) }
        ))
    }

    private func registerHotkeys() {
        let result = hotKeys.register([shelfChord, captureChord]) { [weak self] chord in
            if chord == self?.captureChord { self?.beginQuickCapture() } else { self?.openShelf() }
        }
        UserDefaults.standard.set(result == .conflict, forKey: "ledge.hotkey.conflict")
        if result == .conflict { openSettings() }
    }

    private func openShelf() { open(.home) }

    private func configureFeatureServices() {
        do {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ledge", isDirectory: true)
            try Self.migrateShelfContainerIfNeeded(destination: root)
            let repository = try SQLiteShelfStore(root: root, keyStore: KeychainMasterKeyStore(service: Bundle.main.bundleIdentifier ?? "com.ledge.app"))
            let service = QuickCaptureService(source: FrontmostApplicationSourceContextProvider(), panel: panelCoordinator, repository: repository)
            quickCaptureService = service
            captureStore = CaptureStore(service: service)
            audioHardware = AudioHardwareService(client: SystemCoreAudioClient())
            clipboardStore = ClipboardStore(repository: repository)
            clipboardMonitor = ClipboardMonitor(
                pasteboard: SystemPasteboardClient(),
                activeApps: WorkspaceActiveApplicationProvider(),
                policy: ClipboardPolicy(excludedBundleIDs: ["com.1password.1password", "com.agilebits.onepassword7", "com.apple.keychainaccess"]),
                repository: repository
            )
            meetingStore = MeetingStore(provider: EventKitMeetingService())
        } catch {
            quickCaptureService = nil
            captureStore = nil
        }
    }

    private static func migrateShelfContainerIfNeeded(destination: URL) throws {
        let source = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Containers/com.ledge.app/Data/Library/Application Support/Ledge", isDirectory: true)
        guard source.standardizedFileURL != destination.standardizedFileURL,
              FileManager.default.fileExists(atPath: source.appendingPathComponent("ledge.sqlite").path),
              !FileManager.default.fileExists(atPath: destination.appendingPathComponent("ledge.sqlite").path) else { return }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw PlatformError.unavailable("Existing shelf data needs migration. Both old and new storage locations exist; no files were overwritten.")
        }
        // Copy the complete SQLite/WAL/vault set. The original remains available
        // for recovery; no key is replaced and no source files are deleted.
        try FileManager.default.copyItem(at: source, to: destination)
        try Data("Copied from previous Ledge sandbox; original preserved.\n".utf8).write(to: destination.appendingPathComponent("migration-v1-receipt.txt"), options: .atomic)
    }

    private func openAudioControls() {
        installShelfView(appCoordinator.resolution, route: .audioControls)
        panelCoordinator.reveal(.audioControls, reason: .statusItem, screenID: Self.screenDescriptor(NSScreen.main)?.id)
        refreshAudio()
    }

    private func openSearchClipboard() {
        open(.searchClipboard)
        startClipboardMonitoringIfEnabled()
    }

    private func toggleClipboardPause() {
        clipboardPaused.toggle()
        UserDefaults.standard.set(clipboardPaused, forKey: "ledge.clipboard.paused")
        guard let monitor = clipboardMonitor else { return }
        Task { await monitor.setUserPaused(clipboardPaused) }
    }

    private func startClipboardMonitoringIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "ledge.clipboard.enabled"), clipboardTask == nil, let monitor = clipboardMonitor else { return }
        clipboardTask = Task { @MainActor [weak self] in
            await monitor.setOptedIn(true)
            await monitor.setUserPaused(self?.clipboardPaused ?? false)
            while !Task.isCancelled {
                await monitor.pollOnce()
                try? await Task.sleep(for: .seconds(1))
            }
            self?.clipboardTask = nil
        }
    }

    private func refreshAudio() {
        guard let audioHardware else { return }
        Task { @MainActor [weak self] in
            try? await audioHardware.refresh()
            guard let self else { return }
            self.audioSnapshot = await audioHardware.latest
            self.installShelfView(self.appCoordinator.resolution, route: .audioControls)
        }
    }

    private func requestMeetingAccess() {
        guard let meetingStore else { return }
        Task { @MainActor in await meetingStore.requestCalendarAccess() }
    }

    private func setOutputVolume(_ value: Float) {
        guard let audioHardware else { return }
        Task { @MainActor [weak self] in
            try? await audioHardware.setOutputVolume(value)
            self?.refreshAudio()
        }
    }

    private func setOutputMuted(_ muted: Bool) {
        guard let audioHardware else { return }
        Task { @MainActor [weak self] in
            try? await audioHardware.setOutputMuted(muted)
            self?.refreshAudio()
        }
    }

    private func setInputMuted(_ muted: Bool) {
        guard let audioHardware else { return }
        Task { @MainActor [weak self] in
            try? await audioHardware.setInputDeviceMuted(muted)
            self?.refreshAudio()
        }
    }

    private func beginQuickCapture() {
        captureStore?.reset()
        installShelfView(appCoordinator.resolution, route: .quickCapture)
        guard let service = quickCaptureService else { open(.quickCapture); return }
        Task { @MainActor [weak self] in
            do { try await service.beginCapture(screenID: Self.screenDescriptor(NSScreen.main)?.id) }
            catch { self?.open(.quickCapture) }
        }
    }

    private func open(_ route: ShelfRoute) {
        installShelfView(appCoordinator.resolution, route: route)
        panelCoordinator.reveal(route, reason: .statusItem, screenID: Self.screenDescriptor(NSScreen.main)?.id)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Ledge Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView()); window.center(); settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        #if LEDGE_UITESTING
        diagnostics.settings = "opened"
        #endif
    }

    private static func screenDescriptor(_ screen: NSScreen?) -> ScreenDescriptor? {
        guard let screen else { return nil }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return ScreenDescriptor(
            id: "display:\(displayID)",
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: .init(top: screen.safeAreaInsets.top, left: screen.safeAreaInsets.left, bottom: screen.safeAreaInsets.bottom, right: screen.safeAreaInsets.right),
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            isBuiltIn: CGDisplayIsBuiltin(displayID) != 0
        )
    }

    private func resolvedScreenDescriptor(_ screenID: String?) -> ScreenDescriptor? {
        #if LEDGE_UITESTING
        if let fixture = fixtureScreenDescriptor(AppEnvironment.uiTesting), screenID == nil || screenID == fixture.id { return fixture }
        #endif
        let descriptors = NSScreen.screens.compactMap(Self.screenDescriptor)
        if let screenID, let match = descriptors.first(where: { $0.id == screenID }) { return match }
        return descriptors.first(where: { $0.isBuiltIn && $0.safeAreaInsets.top > 0 }) ?? descriptors.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? descriptors.first
    }

    #if LEDGE_UITESTING
    private func applyUITestFixture() {
        let fixture = AppEnvironment.uiTesting
        diagnostics.screen = fixture.screen
        diagnostics.hotKeyResult = fixture.hotKeyResult
        diagnostics.action = fixture.action ?? "none"
        diagnostics.presentationSafe = fixture.presentationSafe ? "enabled" : "disabled"
        diagnostics.statusMenu = statusItem == nil ? "unavailable" : "available"
        if fixture.audioCard {
            diagnostics.audioFixture = "audio-card"
            diagnostics.audioInputMute = "unsupported"
        }

        guard let screen = fixtureScreenDescriptor(fixture) else {
            diagnostics.screenGeometry = "disconnected"
            return
        }
        diagnostics.screenGeometry = "x=\(Int(screen.frame.minX));top=\(Int(screen.safeAreaInsets.top))"
        if fixture.screen == "full-screen" || fixture.presentationSafe {
            panelCoordinator.dismiss(reason: fixture.presentationSafe ? .presentationSafe : .spaceChanged)
            diagnostics.shelfPresentation = "hidden"
        } else {
            panelCoordinator.showPeek(on: screen, contentSize: CGSize(width: 420, height: 88))
            diagnostics.shelfPresentation = "peek"
        }
        if fixture.action == "escape" {
            panelCoordinator.dismiss(reason: .escape)
            diagnostics.shelfPresentation = "hidden"
        }
        if fixture.hotKeyResult == "conflict" { openSettings() }
    }

    private func fixtureScreenDescriptor(_ fixture: UITestFixture) -> ScreenDescriptor? {
        let frame: CGRect
        switch fixture.screen {
        case "negative-coordinate": frame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        case "mirrored": frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        case "disconnected": return nil
        default: frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        }
        let topInset: CGFloat = fixture.screen == "notched" ? 37 : 0
        return ScreenDescriptor(
            id: fixture.screen,
            frame: frame,
            visibleFrame: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - topInset),
            safeAreaInsets: .init(top: topInset, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: topInset == 0 ? nil : CGRect(x: frame.minX, y: frame.maxY - topInset, width: 632, height: topInset),
            auxiliaryTopRightArea: topInset == 0 ? nil : CGRect(x: frame.maxX - 632, y: frame.maxY - topInset, width: 632, height: topInset),
            isBuiltIn: fixture.screen == "notched"
        )
    }

    private func showUITestDiagnostics() {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 340, height: 220), styleMask: [.titled], backing: .buffered, defer: false)
        panel.contentView = NSHostingView(rootView: UITestDiagnosticsView(diagnostics: diagnostics))
        panel.makeKeyAndOrderFront(nil)
        diagnosticsPanel = panel
    }
    #endif
}
