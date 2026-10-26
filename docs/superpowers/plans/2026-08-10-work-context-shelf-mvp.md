# Ledge Work-Context Shelf MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-first macOS shelf that reveals the next useful action through hover or a hotkey, supports MVP features 1-6, and disappears without disrupting the user's current app.

**Architecture:** Ledge is a single-process, sandboxed accessory app. AppKit owns screen geometry, a nonactivating `NSPanel`, the recovery status item, drag/drop, and platform adapters; SwiftUI renders small feature views; immutable `Sendable` domain values cross into actor-isolated services for storage, EventKit, Core Audio, ScreenCaptureKit, and pasteboard access. Features submit sanitized action candidates to a deterministic local resolver instead of becoming a collection of persistent widgets.

**Tech Stack:** macOS 15+, Swift 6 language mode with complete concurrency checking, SwiftUI, AppKit, EventKit, Core Audio, ScreenCaptureKit, CryptoKit, Security/Keychain, SQLite3, Core Image, XCTest/Swift Testing, XCUITest, and `xcodebuild`.

## Global Constraints

- Deployment target: macOS 15.0; build a universal macOS binary and test the supported Intel and Apple-silicon paths in CI or on hardware.
- Toolchain floor: Xcode 16.3 or newer with Swift 6 language mode and complete strict-concurrency checking. Xcode 16.3 supplies the macOS 15.4 SDK needed to compile the availability-gated pasteboard privacy APIs. This checkout currently has Command Line Tools for the macOS 15.2 SDK only, so a full Xcode installation is an implementation prerequisite.
- Distribution baseline: Mac App Store-compatible App Sandbox from the first runnable build.
- Process model: one GUI process; no privileged helper, launch daemon, login helper, kernel/system extension, or installer package.
- API boundary: public Apple APIs only. Never import or dynamically look up MediaRemote, private CGS symbols, private frameworks, or Sapphire implementation code.
- Licensing boundary: Sapphire is product research only. Implement from this clean-room plan and official Apple documentation; do not consult Sapphire's source tree while coding, and do not copy or derive code/assets from its AGPL-3.0 repository.
- Network boundary: no network client entitlement, analytics, crash uploader, sync, remote flags, updater, account, cloud QR service, or plugin download in the MVP.
- Permission boundary: request Calendar and Screen Recording separately and only when the person invokes the related feature. Do not request Accessibility, Input Monitoring, Apple Events, microphone capture, Contacts, or Bluetooth.
- State boundary: domain models are immutable value types. Framework mutation and caches stay inside their owning actor or `@MainActor` adapter.
- Privacy boundary: no clipboard text, capture body, calendar title/notes, meeting URL, filename, source-app name, or QR payload in logs, diagnostics, crash artifacts, or signposts.
- Testability boundary: platform fakes and launch-argument fixture injection compile only in Debug/UITesting configurations. Release ignores test environment variables/arguments and contains no fake service factory.
- Quality boundary: tests precede implementation, each first-party logic module reaches at least 80% executable-line coverage, and security/geometry/URL/expiry/crypto/file-transaction code reaches at least 90%.
- UX boundary: one primary action and at most two secondary actions in peek state; no dashboard, tab bar, permanent expanded shelf, or second menu bar.
- Recovery boundary: the status item, global hotkey, and normal app launch can each reach Settings. The status item cannot be hidden in the MVP.
- Accessibility boundary: complete keyboard operation, VoiceOver names/roles/values, 44x44-point primary targets, visible focus, 4.5:1 normal-text contrast, reduced-motion behavior, and Escape from every transient state.
- Scope boundary: weather, stocks, face unlock, AI screen sharing, Android/Nearby Share, per-app EQ, window snapping, notifications, focus tools, integrations, and the plugin/widget model remain deferred.

---

## 1. TDD Implementation Tasks

These are the execution gates. Sections 2-9 provide the shared product, architecture, platform, security, performance, and source reference that applies to every task.

Build-manifest rule for every file list below: Tasks 1-6 and 9 add their named source/test targets to `Packages/LedgeKit/Package.swift`; Tasks 2-12 add new app, integration, UI, or performance files to `Ledge.xcodeproj/project.pbxproj` and the shared `Ledge.xcscheme` test action. These manifest edits are required parts of the task even when the list emphasizes the owned source files.

### Task 0: Project Spine and Signed Capability Contract

**Files:**
- Create: `Config/Base.xcconfig`
- Create: `Config/Debug.xcconfig`
- Create: `Config/Release.xcconfig`
- Create: `Ledge.xcodeproj/project.pbxproj`
- Create: `Ledge.xcodeproj/xcshareddata/xcschemes/Ledge.xcscheme`
- Create: `LedgeApp/App/LedgeApp.swift`
- Create: `LedgeApp/App/AppDelegate.swift`
- Create: `LedgeApp/App/AppEnvironment.swift`
- Create: `LedgeApp/Resources/Info.plist`
- Create: `LedgeApp/Resources/Ledge.entitlements`
- Create: `Packages/LedgeKit/Package.swift`
- Create: `Packages/LedgeKit/Sources/LedgeDomain/ActionCandidate.swift`
- Create: `Packages/LedgeKit/Sources/LedgeDomain/ExternalURLPolicy.swift`
- Create: `Packages/LedgeKit/Sources/LedgeDomain/ShelfItem.swift`
- Create: `Packages/LedgeKit/Sources/LedgeDomain/PlatformProtocols.swift`
- Create: `Packages/LedgeKit/Tests/LedgeDomainTests/DomainSmokeTests.swift`
- Create: `Packages/LedgeKit/Tests/LedgeDomainTests/ExternalURLPolicyTests.swift`
- Create: `Scripts/verify-public-apis.sh`
- Create: `.github/workflows/ci.yml`
- Create: `docs/architecture/public-api-boundaries.md`
- Create: `docs/compliance/source-provenance.md`

**Interfaces:**
- Consumes: none; this is the root task.
- Produces: the `LedgeDomain` module (including `ActionCandidate`/`ShelfCommand` contracts), a sandboxed `Ledge` app scheme, `AppEnvironment`, and the public-API release scan used by every later task.

- [ ] **Step 1: Write the failing domain smoke test**

```swift
import Foundation
import Testing
@testable import LedgeDomain

@Test("Shelf item defaults remain local and expiring")
func shelfItemDefaults() {
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    let draft = ShelfItemDraft.note("Ship the smallest useful slice", now: now)

    #expect(draft.kind == .note)
    #expect(draft.createdAt == now)
    #expect(draft.expiresAt == now.addingTimeInterval(30 * 86_400))
    #expect(draft.source == nil)
}

@Test("External URLs fail closed at the shared boundary")
func externalURLPolicy() {
    let policy = ExternalURLPolicy(maximumUTF8Bytes: 8_192)

    #expect(policy.validate("https://example.com/runbook").isSuccess)
    #expect(policy.validate("https://user:secret@example.com").isFailure)
    #expect(policy.validate("javascript:alert(1)").isFailure)
    #expect(policy.validate("https://zoom.us.example.com/room").isSuccess) // base syntax only
}
```

- [ ] **Step 2: Run it and verify the project does not exist yet**

Run: `rtk swift test --package-path Packages/LedgeKit`

Expected: FAIL because `Packages/LedgeKit/Package.swift` and `LedgeDomain` do not exist.

- [ ] **Step 3: Create the package and immutable domain baseline**

`Package.swift` declares macOS 15 and these initial products/targets:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LedgeKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "LedgeDomain", targets: ["LedgeDomain"])],
    targets: [
        .target(name: "LedgeDomain"),
        .testTarget(name: "LedgeDomainTests", dependencies: ["LedgeDomain"])
    ]
)
```

Implement `ShelfItemDraft.note` as a pure constructor returning a new value with a 30-day expiry. Define the immutable, feature-neutral `ActionCandidate`, `ActionUrgency`, `Sensitivity`, and typed `ShelfCommand` contracts shown in section 2.4; feature-specific cases may be added exhaustively as their tasks land. Add one shared `ExternalURLPolicy` for capture, handoff, QR, and the base layer of meeting parsing: accept absolute HTTP(S) only, require a valid nonempty host, cap the serialized URL at 8 KiB, and reject credentials, control characters, invalid percent encoding, or malformed/ambiguous hostnames. Create the Xcode app target with `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, warnings as errors in CI, `LSUIElement = true`, and the exact entitlements from section 3.2.

- [ ] **Step 4: Add a nonblocking app launch and recovery surface**

```swift
@main
struct LedgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { SettingsPlaceholderView() }
    }
}
```

`AppDelegate.applicationDidFinishLaunching` must create the status item first, register hotkeys second, and start no permission-gated service. A calendar/audio/storage failure must not prevent Settings or Quit. `AppEnvironment` exposes test factories only under a `LEDGE_UITESTING` compilation condition that is absent from Release; ordinary runtime arguments can never select a fake service.

- [ ] **Step 5: Add the public-API scan and architecture decision**

`Scripts/verify-public-apis.sh` fails if source, linked symbols, or bundle contents contain `MediaRemote`, `CGS` private calls, `ScriptingBridge`, `AXUIElement`, `CGEventPost`, `SMJobBless`, or a non-system embedded executable. The architecture document records: one process, App Sandbox, no network, no universal Now Playing, no global mic-mute promise, and best-effort clipboard source exclusions. Initialize `source-provenance.md` with the clean-room rule and an empty register for non-original code/assets; every later task must update it before introducing such material.

- [ ] **Step 6: Run package, app, and Release checks**

Run:

```bash
rtk swift test --package-path Packages/LedgeKit
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -destination 'platform=macOS'
rtk xcodebuild build -project Ledge.xcodeproj -scheme Ledge -configuration Release
rtk proxy ./Scripts/verify-public-apis.sh
```

Expected: all tests pass, the sandboxed Release app opens without a permission prompt, Settings is reachable from the status item, and the scan reports no forbidden API.

- [ ] **Step 7: Commit the spine**

```bash
rtk git add Config Ledge.xcodeproj LedgeApp Packages Scripts .github docs/architecture docs/compliance
rtk git commit -m "chore: establish sandboxed macOS app spine"
```

### Task 1: Encrypted Repository, Expiry, and Crash Recovery

**Files:**
- Create: `Packages/LedgeKit/Sources/LedgeDomain/ShelfRepository.swift`
- Create: `Packages/LedgeKit/Sources/LedgeStorage/SQLiteConnection.swift`
- Create: `Packages/LedgeKit/Sources/LedgeStorage/ShelfMigration.swift`
- Create: `Packages/LedgeKit/Sources/LedgeStorage/SQLiteShelfStore.swift`
- Create: `Packages/LedgeKit/Sources/LedgeStorage/KeychainMasterKeyStore.swift`
- Create: `Packages/LedgeKit/Sources/LedgeStorage/PayloadEnvelope.swift`
- Create: `Packages/LedgeKit/Sources/LedgeStorage/EncryptedPayloadVault.swift`
- Create: `Packages/LedgeKit/Sources/LedgeStorage/ExpiryScheduler.swift`
- Create: `Packages/LedgeKit/Tests/LedgeStorageTests/EncryptedPayloadVaultTests.swift`
- Create: `Packages/LedgeKit/Tests/LedgeStorageTests/SQLiteShelfStoreTests.swift`
- Create: `LedgeIntegrationTests/PersistenceRecoveryTests.swift`

**Interfaces:**
- Consumes: `ShelfItem`, `ShelfItemDraft`, `ShelfItemKind` from Task 0.
- Produces: `ShelfRepository`, `SQLiteShelfStore`, `EncryptedPayloadVault`, `PurgeReport`, and `ExpiryScheduler` for capture, clipboard, tray, and screenshot tasks.

- [ ] **Step 1: Write failing encryption and plaintext-leak tests**

```swift
import Foundation
import Testing
@testable import LedgeStorage

@Test("Encrypted payload round trips without plaintext at rest")
func encryptedRoundTrip() async throws {
    let root = try TestDirectory.make()
    let key = Data(repeating: 0x2A, count: 32)
    let vault = EncryptedPayloadVault(root: root.url, keyStore: FixedKeyStore(key))
    let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let secret = Data("customer roadmap and token sk_live_example".utf8)

    try await vault.write(secret, itemID: id, kind: .note)
    let stored = try Data(contentsOf: root.url.appending(path: "Vault/\(id.uuidString).ledge"))

    #expect(stored.range(of: secret) == nil)
    #expect(try await vault.read(itemID: id, kind: .note) == secret)
}

@Test("Wrong key fails closed")
func wrongKeyFailsClosed() async throws {
    let root = try TestDirectory.make()
    let id = UUID()
    try await EncryptedPayloadVault(
        root: root.url,
        keyStore: FixedKeyStore(Data(repeating: 1, count: 32))
    ).write(Data("private".utf8), itemID: id, kind: .clipboardText)

    let reader = EncryptedPayloadVault(
        root: root.url,
        keyStore: FixedKeyStore(Data(repeating: 2, count: 32))
    )
    await #expect(throws: PayloadVaultError.authenticationFailed) {
        try await reader.read(itemID: id, kind: .clipboardText)
    }
}
```

- [ ] **Step 2: Run the tests to verify RED**

Run: `rtk swift test --package-path Packages/LedgeKit --filter LedgeStorageTests`

Expected: FAIL because `LedgeStorage` and its vault types do not exist.

- [ ] **Step 3: Implement Keychain and chunked AES-GCM storage**

Implement these exact entry points:

```swift
public protocol MasterKeyStoring: Sendable {
    func loadOrCreate() throws -> SymmetricKey
}

public actor EncryptedPayloadVault {
    public init(root: URL, keyStore: any MasterKeyStoring)
    public func write(_ data: Data, itemID: UUID, kind: ShelfItemKind) async throws
    public func importFile(from source: URL, itemID: UUID, kind: ShelfItemKind)
        -> AsyncThrowingStream<ImportProgress, Error>
    public func read(itemID: UUID, kind: ShelfItemKind) async throws -> Data
    public func export(itemID: UUID, kind: ShelfItemKind, to destination: URL) async throws
    public func delete(itemID: UUID) async throws
    public func reconcile() async throws -> ReconciliationReport
}
```

Use the `LEDGE1` chunk format from section 3.4, atomic temporary writes, mode `0600`, authenticated metadata, and backup exclusion on every Ledge data directory. Reject an envelope whose magic, UUID, kind, declared length, chunk size, nonce sequence, manifest tag, chunk length, or chunk authentication tag is invalid.

- [ ] **Step 4: Implement SQLite migrations and repository transactions**

Apply the schema from section 3.3 in one transaction. Use prepared statements and bound parameters for every runtime value; never interpolate identifiers, search text, paths, or metadata into SQL. Encode dates as Unix seconds and UUIDs as uppercase strings. Derive the dedupe digest with `HMAC<SHA256>` and the digest subkey; do not store an ordinary SHA hash of text. Map database rows into fresh immutable domain values after decrypting the payload.

- [ ] **Step 5: Add interrupted-operation tests**

Test a crash after each import stage: row inserted, temp payload complete, atomic rename complete, and ready-state update complete. `reconcile()` must either finish a valid operation or remove its orphaned state; repeated reconciliation produces the same report and filesystem state.

- [ ] **Step 6: Add expiry tests with a fake wall clock**

```swift
@Test("Expiry removes ordinary items and preserves favorites")
func expiryPolicy() async throws {
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    let repository = try await TestRepository.make(now: now)
    let ordinary = try await repository.insert(.note("short lived", now: now))
    let favorite = try await repository.insert(.note("keep", now: now))
    _ = try await repository.setFavorite(id: favorite.id, isFavorite: true)

    let report = try await repository.purgeExpired(before: now.addingTimeInterval(31 * 86_400))

    #expect(report.deletedIDs == [ordinary.id])
    #expect(try await repository.item(id: favorite.id)?.isFavorite == true)
}
```

Add a second assertion fixture where a pinned 30-day capture is eight days old: the item and content remain, but its decrypted `source` is `nil` and no retired source metadata is present in the rewritten envelope.

- [ ] **Step 7: Run tests and scan all persistence artifacts**

Run:

```bash
rtk swift test --package-path Packages/LedgeKit --filter LedgeStorageTests
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -only-testing:LedgeIntegrationTests/PersistenceRecoveryTests
rtk rg -a -n 'customer roadmap|sk_live_example|short lived' .build/TestVaults
```

Expected: tests pass and the final scan returns no matches.

- [ ] **Step 8: Commit storage**

```bash
rtk git add Packages/LedgeKit LedgeIntegrationTests
rtk git commit -m "feat: add encrypted local shelf storage"
```

### Task 2: Adaptive Shell, Hotkeys, and Recovery Menu

**Files:**
- Create: `Packages/LedgeKit/Sources/ShellFeature/ShellState.swift`
- Create: `Packages/LedgeKit/Sources/ShellFeature/ShellReducer.swift`
- Create: `Packages/LedgeKit/Sources/ShellFeature/ScreenDescriptor.swift`
- Create: `Packages/LedgeKit/Sources/ShellFeature/ShelfGeometryResolver.swift`
- Create: `Packages/LedgeKit/Sources/ShellFeature/ShellPanel.swift`
- Create: `Packages/LedgeKit/Sources/ShellFeature/ShellPanelCoordinator.swift`
- Create: `Packages/LedgeKit/Sources/ShellFeature/HoverTriggerPanel.swift`
- Create: `Packages/LedgeKit/Sources/ShellFeature/CarbonHotKeyRegistrar.swift`
- Create: `Packages/LedgeKit/Sources/ShellFeature/StatusItemController.swift`
- Create: `Packages/LedgeKit/Sources/ShellFeature/ShelfRootView.swift`
- Create: `Packages/LedgeKit/Tests/ShellFeatureTests/ShelfGeometryResolverTests.swift`
- Create: `Packages/LedgeKit/Tests/ShellFeatureTests/ShellReducerTests.swift`
- Create: `LedgeUITests/ShellLifecycleUITests.swift`
- Create: `LedgeUITests/RecoverySurfaceUITests.swift`

**Interfaces:**
- Consumes: `WallClock` and app composition from Tasks 0-1.
- Produces: `ShellPanelControlling`, `ExternalInteractionToken`, `ScreenDescriptor`, `ShelfRoute`, `ShellState`, and `HotKeyRegistering` used by every feature.

- [ ] **Step 1: Write failing geometry tests for real screen shapes**

```swift
@Test("Notched placement stays below the camera safe area")
func notchedPlacement() {
    let screen = ScreenDescriptor(
        id: "built-in",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945),
        safeAreaInsets: .init(top: 37, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 632, height: 37),
        auxiliaryTopRightArea: CGRect(x: 880, y: 945, width: 632, height: 37),
        isBuiltIn: true
    )

    let placement = ShelfGeometryResolver().placement(
        screen: screen,
        contentSize: CGSize(width: 420, height: 88)
    )

    #expect(placement.frame.midX == screen.frame.midX)
    #expect(placement.frame.maxY <= 945)
    #expect(screen.visibleFrame.contains(placement.frame))
}

@Test("Disconnected negative-coordinate display falls back without stale geometry")
func disconnectedDisplayFallback() {
    let state = ShellReducer.reduce(
        .expanded(route: .meeting, screenID: "removed"),
        .screensChanged(availableIDs: ["main"], fallbackID: "main")
    )
    #expect(state == .hidden(pendingScreenID: "main"))
}
```

- [ ] **Step 2: Run the shell tests to verify RED**

Run: `rtk swift test --package-path Packages/LedgeKit --filter ShellFeatureTests`

Expected: FAIL because the shell target does not exist.

- [ ] **Step 3: Implement the pure geometry resolver and reducer**

The resolver computes `topInset = max(safeAreaInsets.top, frame.maxY - visibleFrame.maxY)`, centers the desired width, sets `maxY = frame.maxY - topInset`, and clamps the complete rectangle to `visibleFrame`. It never checks machine identifiers or hard-codes a notch width.

The reducer returns new states for hover dwell, pointer exit, hotkey toggle, expansion, action completion, Escape, outside click, full-screen suppression, presentation-safe changes, screen removal, Space changes, and begin/end of a typed external-interaction lease. Reducer code performs no AppKit calls. A lease keeps an explicitly opened `NSSavePanel`, permission prompt, or sharing picker from being mistaken for an outside dismissal and is always released on success, cancellation, failure, or timeout.

- [ ] **Step 4: Implement nonactivating AppKit panels**

Create the main panel with:

```swift
let panel = NSPanel(
    contentRect: .zero,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: true
)
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
panel.isFloatingPanel = true
panel.becomesKeyOnlyIfNeeded = true
panel.hidesOnDeactivate = false
panel.isOpaque = false
panel.backgroundColor = .clear
```

The hover trigger uses `NSTrackingArea` and exists only on eligible displays. It is four points tall on opt-in notchless/external displays and does not span the screen. Disable auto-hover on likely/unknown full-screen Spaces; explicit hotkey reveal remains.

Peek closes from tracking exit plus a short cancellable timeout. Interactive/expanded state makes the `ShellPanel` key and closes on `NSWindow.didResignKeyNotification`, Escape, or its own local click handling unless a typed external-interaction lease is active. Do not install a global mouse/keyboard monitor or event tap merely to detect outside clicks.

- [ ] **Step 5: Implement public hotkey registration and conflict recovery**

Wrap `RegisterEventHotKey`/`UnregisterEventHotKey` on `@MainActor`. Register only the two exact configured chords, never inspect other keystrokes, and return `.conflict`, `.unsupported`, or `.registered`. A conflict opens Shortcut Settings from the status menu; it never blocks launch.

- [ ] **Step 6: Add lifecycle UI tests**

Use launch arguments to inject notched, notchless, secondary-menu-bar, negative-coordinate, mirrored, and disconnected screen descriptors. Assert one expanded shelf, Escape dismissal, focus restoration, reset position, status-item recovery after hotkey failure, no automatic reveal in full-screen fixtures, and correct retain/dismiss behavior around a fake external-interaction lease.

- [ ] **Step 7: Run the shell and app suites**

Run:

```bash
rtk swift test --package-path Packages/LedgeKit --filter ShellFeatureTests
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -only-testing:LedgeUITests/ShellLifecycleUITests -only-testing:LedgeUITests/RecoverySurfaceUITests
```

Expected: all geometry/state/UI tests pass and no test requires Accessibility or Input Monitoring.

- [ ] **Step 8: Commit the shell**

```bash
rtk git add Packages/LedgeKit LedgeApp LedgeUITests
rtk git commit -m "feat: add adaptive recoverable shelf shell"
```

### Task 3: Keyboard-First Note, Task, and Link Capture

**Files:**
- Create: `Packages/LedgeKit/Sources/CaptureFeature/CaptureModels.swift`
- Create: `Packages/LedgeKit/Sources/CaptureFeature/CapturePreferences.swift`
- Create: `Packages/LedgeKit/Sources/CaptureFeature/SourceContextProvider.swift`
- Create: `Packages/LedgeKit/Sources/CaptureFeature/QuickCaptureService.swift`
- Create: `Packages/LedgeKit/Sources/CaptureFeature/CaptureStore.swift`
- Create: `Packages/LedgeKit/Sources/CaptureFeature/QuickCaptureView.swift`
- Create: `Packages/LedgeKit/Tests/CaptureFeatureTests/QuickCaptureServiceTests.swift`
- Create: `Packages/LedgeKit/Tests/CaptureFeatureTests/CaptureReducerTests.swift`
- Create: `LedgeUITests/QuickCaptureFlowUITests.swift`

**Interfaces:**
- Consumes: `ShelfRepository`, `SourceContext`, and `ShellPanelControlling` from Tasks 0-2.
- Produces: `CaptureStore`, `CaptureDraft`, `CaptureSourcePolicy`, and quick-capture action candidates for Task 10.

- [ ] **Step 1: Write failing validation and source-order tests**

```swift
@Test("Source app is frozen before Ledge becomes key")
func sourceSnapshotPrecedesReveal() async throws {
    let source = RecordingSourceContextProvider(
        result: SourceContext(
            bundleIdentifier: "com.example.Editor",
            applicationName: "Editor",
            capturedAt: .distantPast
        )
    )
    let panel = RecordingPanelController()
    let service = QuickCaptureService(source: source, panel: panel, repository: InMemoryShelfRepository())

    try await service.beginCapture(at: Date(timeIntervalSince1970: 100))

    #expect(source.readSequence == 1)
    #expect(panel.revealSequence == 2)
}

@Test("Unsafe content and context link schemes are rejected")
func rejectsUnsafeLink() {
    #expect(CaptureDraft.parse("l javascript:alert(1)") == .failure(.unsupportedURLScheme))
    #expect(CaptureDraft.parse("l https://example.com/runbook").isSuccess)
    #expect(CaptureContextURL.parse("data:text/plain,secret") == .failure(.unsupportedURLScheme))
}

@Test("Source-free capture never queries the frontmost application")
func sourceFreeCaptureSkipsProvider() async throws {
    let source = RecordingSourceContextProvider(result: .fixture)
    let service = QuickCaptureService(
        source: source,
        sourcePolicy: .neverAttach,
        panel: RecordingPanelController(),
        repository: InMemoryShelfRepository()
    )

    try await service.beginCapture(at: .distantPast)

    #expect(source.readCount == 0)
}
```

- [ ] **Step 2: Run the capture tests to verify RED**

Run: `rtk swift test --package-path Packages/LedgeKit --filter CaptureFeatureTests`

Expected: FAIL because `CaptureFeature` does not exist.

- [ ] **Step 3: Implement capture parsing and storage**

Accept `n `, `t `, and `l ` prefixes, plus an explicit type picker. Trim surrounding whitespace, reject empty values, cap UTF-8 content at 64 KiB, and validate every link through `ExternalURLPolicy`. A note, task, or screenshot may also carry one explicitly supplied HTTP(S) context URL, entered through the context field or dropped by the user; never read a browser or the general pasteboard to populate it automatically. Save through `ShelfRepository.insert`; do not add a parallel capture database. `CaptureSourcePolicy` is a typed local preference with `.attachApplication` and `.neverAttach`; when it is off, `QuickCaptureService` must not call the source provider. `CaptureDraft` carries an optional immutable source snapshot, and saving never re-queries the active app.

- [ ] **Step 4: Implement keyboard and focus behavior**

When source attachment is enabled, the capture panel snapshots the prior frontmost app, becomes key without activating a regular app window, focuses the editor, and supports Tab type changes, Command-L to reveal/focus the optional context-URL field, Command-Return save, and Escape cancel. Show attached app and explicit URL as removable context chips; “Remove all context” discards both before save. Privacy Settings owns the persistent “Attach source app” switch and explains that disabling it prevents the app lookup on future captures; an explicitly entered URL remains an intentional per-capture choice. Both save and cancel dismiss and release key status. Do not inspect selected text, window title, or browser state.

- [ ] **Step 5: Add UI journeys**

Cover note save, task completion, valid link, explicit context URL, invalid content/context URL recovery, Remove all context, source-free privacy option, cancel without persistence, hotkey conflict fallback through the status menu, relaunch persistence, and focus return to the fixture app.

- [ ] **Step 6: Run tests and verify plaintext is absent**

Run:

```bash
rtk swift test --package-path Packages/LedgeKit --filter CaptureFeatureTests
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -only-testing:LedgeUITests/QuickCaptureFlowUITests
rtk rg -a -n 'Ship the smallest useful slice|example.com/runbook' .build/TestVaults
```

Expected: tests pass and the persistence scan returns no matches.

- [ ] **Step 7: Commit quick capture**

```bash
rtk git add Packages/LedgeKit LedgeUITests
rtk git commit -m "feat: add keyboard-first quick capture"
```

### Task 4: Privacy-Safe Clipboard Capture, Search, and Favorites

**Files:**
- Create: `Packages/LedgeKit/Sources/ClipboardFeature/PasteboardClient.swift`
- Create: `Packages/LedgeKit/Sources/ClipboardFeature/ClipboardPolicy.swift`
- Create: `Packages/LedgeKit/Sources/ClipboardFeature/SensitiveAppsPolicy.swift`
- Create: `Packages/LedgeKit/Sources/ClipboardFeature/ClipboardMonitor.swift`
- Create: `Packages/LedgeKit/Sources/ClipboardFeature/ClipboardSearch.swift`
- Create: `Packages/LedgeKit/Sources/ClipboardFeature/ClipboardStore.swift`
- Create: `Packages/LedgeKit/Sources/ClipboardFeature/ClipboardShelfView.swift`
- Create: `LedgeApp/Resources/SensitiveApps.json`
- Create: `Packages/LedgeKit/Tests/ClipboardFeatureTests/ClipboardPolicyTests.swift`
- Create: `Packages/LedgeKit/Tests/ClipboardFeatureTests/ClipboardMonitorTests.swift`
- Create: `Packages/LedgeKit/Tests/ClipboardFeatureTests/ClipboardSearchTests.swift`
- Create: `LedgeIntegrationTests/PasteboardMonitorIntegrationTests.swift`
- Create: `LedgeUITests/ClipboardFlowUITests.swift`

**Interfaces:**
- Consumes: `ShelfRepository`, `WallClock`, `SourceContext`, and shell routes.
- Produces: `ClipboardHistoryProviding`, `ClipboardSnapshot`, pause/clear actions, and clipboard action candidates.

- [ ] **Step 1: Write the fail-closed exclusion test before the monitor**

```swift
@Test("Excluded app advances watermark without reading clipboard content")
func excludedAppNeverReads() async throws {
    let pasteboard = FakePasteboard(changeCount: 12, text: "never persist me")
    let apps = FakeActiveApps(previous: "com.example.Passwords", current: "com.example.Passwords")
    let policy = ClipboardPolicy(excludedBundleIDs: ["com.example.Passwords"])
    let monitor = ClipboardMonitor(
        pasteboard: pasteboard,
        activeApps: apps,
        policy: policy,
        repository: InMemoryShelfRepository()
    )

    await monitor.pollOnce()

    #expect(await pasteboard.contentReadCount == 0)
    #expect(await monitor.watermark == 12)
}

@Test("Unknown activation transition fails closed")
func unknownTransitionFailsClosed() async throws {
    let decision = ClipboardPolicy(excludedBundleIDs: []).decision(
        previousBundleID: "com.example.Editor",
        currentBundleID: nil,
        declaredTypes: [.string]
    )
    #expect(decision == .skip(.uncertainSource))
}
```

- [ ] **Step 2: Run clipboard tests to verify RED**

Run: `rtk swift test --package-path Packages/LedgeKit --filter ClipboardFeatureTests`

Expected: FAIL because the clipboard target does not exist.

- [ ] **Step 3: Implement an explicit opt-in monitor**

`PasteboardClient` exposes `changeCount`, a Ledge-owned `PasteboardAccessState`, declared types, bounded text/URL reads, and writes. On macOS 15.4 and later, the AppKit adapter maps availability-gated `NSPasteboard.accessBehavior` into `.default`, `.ask`, `.alwaysAllow`, or `.alwaysDeny`; earlier systems return `.legacyUnavailable`. On 15.4+, the background scheduler runs only in `.alwaysAllow`. For `.default` or `.ask`, show one explicit Grant Access action that performs at most one user-initiated probe, rechecks state, then pauses and links to System Settings unless it becomes `.alwaysAllow`; never poll in a state that can repeatedly prompt. Legacy systems may run after Ledge's own opt-in. `ClipboardMonitor` also pauses on session lock, sleep, user pause, and `.alwaysDeny`; applies timer tolerance; and reads content only after a changed count and an allow decision.

Treat transient/concealed pasteboard type strings as defense in depth, not a guarantee. Apply app exclusion and activation-transition checks before calling any content API. Never persist images, files, rich text, strings over 64 KiB, or non-HTTP(S) URLs.

- [ ] **Step 4: Implement encrypted dedupe, retention, and in-memory search**

Use the repository's keyed digest to deduplicate. A repeated item creates a replacement value with updated recency and usage count. Decrypt at most 500 entries into the actor-owned search cache; normalize with case/diacritic folding in memory. Favorites sort first and up to 100 are exempt from automatic expiry.

- [ ] **Step 5: Implement keyboard UI and self-write suppression**

Support Command-F, arrows, Return to copy, Command-Shift-F to favorite, Delete, Clear All confirmation, Pause, and Escape. After writing a selected entry, record the returned/change `changeCount` before resuming monitoring so Ledge does not capture itself.

- [ ] **Step 6: Add permission and privacy integration tests**

Cover `.default`, `.ask`, `.alwaysAllow`, `.alwaysDeny`, `.legacyUnavailable`, lock/sleep, Low Power interval, excluded app, app transition race, transient type, oversized text, duplicate, self-write, clear all, and restart. Scan SQLite, vault metadata, cache directories, logs, and diagnostics for the forbidden fixture strings.

- [ ] **Step 7: Run all clipboard checks**

Run:

```bash
rtk swift test --package-path Packages/LedgeKit --filter ClipboardFeatureTests
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -only-testing:LedgeIntegrationTests/PasteboardMonitorIntegrationTests -only-testing:LedgeUITests/ClipboardFlowUITests
```

Expected: all tests pass; denied access creates no prompt loop; excluded/uncertain sources cause zero content reads.

- [ ] **Step 8: Commit clipboard shelf**

```bash
rtk git add Packages/LedgeKit LedgeApp LedgeIntegrationTests LedgeUITests
rtk git commit -m "feat: add private opt-in clipboard shelf"
```

### Task 5: Next Meeting and Presentation-Safe Redaction

**Files:**
- Create: `Packages/LedgeKit/Sources/MeetingFeature/MeetingModels.swift`
- Create: `Packages/LedgeKit/Sources/MeetingFeature/EventKitMeetingService.swift`
- Create: `Packages/LedgeKit/Sources/MeetingFeature/JoinURLParser.swift`
- Create: `Packages/LedgeKit/Sources/MeetingFeature/MeetingSelector.swift`
- Create: `Packages/LedgeKit/Sources/MeetingFeature/PresentationRedactor.swift`
- Create: `Packages/LedgeKit/Sources/MeetingFeature/MeetingStore.swift`
- Create: `Packages/LedgeKit/Sources/MeetingFeature/MeetingCardView.swift`
- Create: `Packages/LedgeKit/Tests/MeetingFeatureTests/MeetingSelectorTests.swift`
- Create: `Packages/LedgeKit/Tests/MeetingFeatureTests/JoinURLParserTests.swift`
- Create: `Packages/LedgeKit/Tests/MeetingFeatureTests/PresentationRedactorTests.swift`
- Create: `LedgeUITests/MeetingCardUITests.swift`
- Create: `LedgeUITests/PresentationSafeUITests.swift`

**Interfaces:**
- Consumes: `MeetingProviding`, `WallClock`, shell routes, and `ActionCandidate`.
- Produces: in-memory `MeetingSnapshot`, Join commands, presentation-redacted render state, and meeting candidates.

- [ ] **Step 1: Write failing meeting selection and URL-policy tests**

```swift
@Test("Selector chooses the next joinable accepted meeting")
func selectsNextMeeting() {
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    let declined = Meeting.fixture(start: now.addingTimeInterval(60), participation: .declined)
    let allDay = Meeting.fixture(start: now.addingTimeInterval(120), isAllDay: true)
    let accepted = Meeting.fixture(start: now.addingTimeInterval(300), participation: .accepted)

    #expect(MeetingSelector().next(from: [declined, allDay, accepted], now: now)?.id == accepted.id)
}

@Test("Join parser rejects executable and credential-bearing URLs")
func rejectsDangerousJoinURLs() {
    let parser = JoinURLParser(knownHTTPSHosts: ["meet.google.com", "zoom.us"])
    #expect(parser.parse("javascript:alert(1)") == nil)
    #expect(parser.parse("https://user:password@example.com/meeting") == nil)
    #expect(parser.parse("Join https://meet.google.com/abc-defg-hij")?.requiresConfirmation == false)
    #expect(parser.parse("https://video.example.org/room")?.requiresConfirmation == true)
}
```

- [ ] **Step 2: Run meeting tests to verify RED**

Run: `rtk swift test --package-path Packages/LedgeKit --filter MeetingFeatureTests`

Expected: FAIL because the meeting target does not exist.

- [ ] **Step 3: Implement the EventKit actor and DTO boundary**

Own one `EKEventStore` inside `EventKitMeetingService`. Request full access only through a user action, fetch a bounded 24-hour interval, translate events immediately into `Sendable` values, and discard `EKEvent` references. Refetch on EventKit change, wake, time-zone change, and day rollover. On revocation, clear snapshots before emitting `.denied`.

- [ ] **Step 4: Implement selection, join parsing, and redaction**

Use URL precedence `event.url`, location, notes. Run every candidate through `ExternalURLPolicy` before applying the stricter meeting-provider/label-boundary rules. Convert agenda to plain text, trim it to four lines/1,000 characters in memory, and never persist it. In manual or mirrored-display safe mode, emit only countdown and Join. Unknown HTTPS hosts require a local confirmation with the exact host.

- [ ] **Step 5: Implement low-wakeup countdown scheduling**

Schedule the next minute boundary while hidden. Switch to one-second updates only while the card is visible and start is within five minutes; cancel immediately on hide. Joining calls `NSWorkspace.open` only after URL validation/confirmation.

- [ ] **Step 6: Add denial and presentation UI tests**

Cover not determined, denied, revoked, empty calendar, next meeting, agenda preview, unsafe URL, unknown host confirmation, manual safe mode, mirrored auto-safe mode, extended external display preference, 30-second explicit reveal, and permission revocation while visible.

- [ ] **Step 7: Run tests and persistence/log scans**

Run:

```bash
rtk swift test --package-path Packages/LedgeKit --filter MeetingFeatureTests
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -only-testing:LedgeUITests/MeetingCardUITests -only-testing:LedgeUITests/PresentationSafeUITests
rtk rg -a -n 'Quarterly acquisition plan|meet.google.com/abc-defg-hij' .build/TestVaults .build/TestLogs
```

Expected: tests pass and no meeting content is found on disk.

- [ ] **Step 8: Commit meetings**

```bash
rtk git add Packages/LedgeKit LedgeUITests
rtk git commit -m "feat: add private next-meeting actions"
```


### Task 6: Handoff Tray Intake, Expiry, Copy, and Move

**Files:**
- Create: `Packages/LedgeKit/Sources/HandoffFeature/IncomingPayload.swift`
- Create: `Packages/LedgeKit/Sources/HandoffFeature/DropDecoder.swift`
- Create: `Packages/LedgeKit/Sources/HandoffFeature/FileDescriptorSource.swift`
- Create: `Packages/LedgeKit/Sources/HandoffFeature/HandoffService.swift`
- Create: `Packages/LedgeKit/Sources/HandoffFeature/ExportService.swift`
- Create: `Packages/LedgeKit/Sources/HandoffFeature/HandoffStore.swift`
- Create: `Packages/LedgeKit/Sources/HandoffFeature/HandoffTrayView.swift`
- Create: `Packages/LedgeKit/Tests/HandoffFeatureTests/DropDecoderTests.swift`
- Create: `Packages/LedgeKit/Tests/HandoffFeatureTests/FileDescriptorSourceTests.swift`
- Create: `Packages/LedgeKit/Tests/HandoffFeatureTests/HandoffServiceTests.swift`
- Create: `Packages/LedgeKit/Tests/HandoffFeatureTests/ExportServiceTests.swift`
- Create: `LedgeIntegrationTests/HandoffFileTransactionTests.swift`
- Create: `LedgeUITests/HandoffFlowUITests.swift`

**Interfaces:**
- Consumes: `ShelfRepository`, `EncryptedPayloadVault`, expiry policy, and shell routes.
- Produces: `HandoffService`, `IncomingPayload`, import progress, copy/move-from-shelf commands, and tray action candidates.

- [ ] **Step 1: Write failing unsafe-input and move-semantics tests**

```swift
@Test("Drop decoder rejects directories and symbolic links")
func rejectsUnsafeFilesystemObjects() async throws {
    let fixture = try FileFixture.makeWithFileDirectoryAndSymlink()
    let decoder = DropDecoder(fileSystem: fixture.fileSystem)

    #expect(try await decoder.decode(fixture.regularFile).isAccepted)
    await #expect(throws: HandoffError.directoryUnsupported) {
        try await decoder.decode(fixture.directory)
    }
    await #expect(throws: HandoffError.symbolicLinkUnsupported) {
        try await decoder.decode(fixture.symbolicLink)
    }
}

@Test("Move from shelf deletes only after verified export")
func moveDeletesAfterExport() async throws {
    let repository = InMemoryShelfRepository.withFile(named: "report.pdf", bytes: Data([1, 2, 3]))
    let exporter = RecordingExporter(result: .verified(byteCount: 3))
    let service = HandoffService(repository: repository, exporter: exporter)

    try await service.export(repository.onlyID, to: URL(filePath: "/chosen/report.pdf"), mode: .moveFromShelf)

    #expect(await exporter.didFinishBeforeDelete)
    #expect(try await repository.item(id: repository.onlyID) == nil)
    #expect(await repository.originalSourceDeleteCount == 0)
}
```

- [ ] **Step 2: Run the handoff tests to verify RED**

Run: `rtk swift test --package-path Packages/LedgeKit --filter HandoffFeatureTests`

Expected: FAIL because `HandoffFeature` does not exist.

- [ ] **Step 3: Implement bounded drop decoding**

Decode regular file URLs, plain text, and URLs from AppKit drag items/`NSItemProvider`; URL items must pass `ExternalURLPolicy`. Reject directories, packages treated as directories, symlinks, aliases that do not resolve to regular files, special nodes, more than 100 inputs, and unavailable security-scoped resources. With the security scope active, open the resolved source using `O_RDONLY | O_CLOEXEC | O_NOFOLLOW`, verify the held descriptor with `fstat`, and stream from that descriptor; never validate a path and reopen it later. Balance every successful `startAccessingSecurityScopedResource()` with `defer { stopAccessingSecurityScopedResource() }`.

- [ ] **Step 4: Implement streaming import and progress**

Before import, check item count, current vault usage, item sizes, and `volumeAvailableCapacityForImportantUsage`. Stream through `EncryptedPayloadVault.importFile`; names remain encrypted metadata, paths use only generated UUIDs, and cancellation removes the partial operation. Emit progress no more than ten times per second.

- [ ] **Step 5: Implement explicit copy and move-from-shelf**

For a single item, use `NSSavePanel`; for multiple items, ask for a folder. In presentation-safe mode, require the bounded explicit sensitive reveal before opening a panel that can display a filename. Hold an external-interaction lease while system panels are active. Write into a UUID temporary destination, verify byte count plus keyed digest, then atomically replace the chosen destination after overwrite confirmation. Copy retains the shelf item. Move-from-shelf calls repository deletion only after verification. Neither path deletes or modifies the original source used during ingest.

- [ ] **Step 6: Add expiry and crash-recovery integration tests**

Cover cancellation, disk full, source disappears, destination exists/cancel overwrite, export failure, corrupted payload, display name with separators/control characters, app quit after import stage, logical expiry, idempotent cleanup, and restore after restart.

- [ ] **Step 7: Add drag/drop and keyboard UI journeys**

Test multi-file drop, text/URL drop, import progress, cancel, 1-hour/1-day/7-day/keep choices, copy, move-from-shelf, Delete, Clear Expired, keyboard selection, and failure messages that reveal no full source path.

- [ ] **Step 8: Run handoff checks**

Run:

```bash
rtk swift test --package-path Packages/LedgeKit --filter HandoffFeatureTests
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -only-testing:LedgeIntegrationTests/HandoffFileTransactionTests -only-testing:LedgeUITests/HandoffFlowUITests
```

Expected: tests pass; every failed/canceled import leaves no incoming blob or ready row; move never touches the source file.

- [ ] **Step 9: Commit tray intake/export**

```bash
rtk git add Packages/LedgeKit LedgeIntegrationTests LedgeUITests
rtk git commit -m "feat: add recoverable handoff tray"
```

### Task 7: Share Sheet, AirDrop, and Explicit QR

**Files:**
- Create: `Packages/LedgeKit/Sources/HandoffFeature/ShareService.swift`
- Create: `Packages/LedgeKit/Sources/HandoffFeature/QRCodeService.swift`
- Create: `Packages/LedgeKit/Tests/HandoffFeatureTests/ShareServiceTests.swift`
- Create: `Packages/LedgeKit/Tests/HandoffFeatureTests/QRCodeServiceTests.swift`
- Modify: `Packages/LedgeKit/Sources/HandoffFeature/HandoffTrayView.swift`
- Modify: `LedgeUITests/HandoffFlowUITests.swift`

**Interfaces:**
- Consumes: ready handoff items and ephemeral export support from Task 6.
- Produces: `ShareService`, `QRCodeService`, explicit Share/AirDrop/QR actions, and guaranteed temporary-export cleanup.

- [ ] **Step 1: Write failing QR policy and share-cleanup tests**

```swift
@Test("QR accepts bounded text and URL but never files")
func qrPolicy() throws {
    let service = QRCodeService(maxUTF8Bytes: 2_048)
    #expect(try service.payload(for: .text("pair this device")) == Data("pair this device".utf8))
    #expect(try service.payload(for: .url(URL(string: "https://example.com")!)).count > 0)
    #expect(throws: QRCodeError.filesUnsupported) {
        try service.payload(for: .file(BinaryDescriptor.fixture))
    }
}

@Test("Share completion removes decrypted temporary export")
func shareCleansTemporaryExport() async throws {
    let temp = RecordingTemporaryExport()
    let service = ShareService(exporter: temp, sharingClient: ImmediateSharingClient(result: .completed))
    try await service.share(.fileFixture)
    #expect(await temp.exists == false)
}
```

- [ ] **Step 2: Run targeted tests to verify RED**

Run: `rtk swift test --package-path Packages/LedgeKit --filter HandoffFeatureTests`

Expected: FAIL because the share/QR types do not exist.

- [ ] **Step 3: Implement Share and AirDrop adapters**

Wrap `NSSharingServicePicker` for general Share and `NSSharingService(named: .sendViaAirDrop)` for direct AirDrop. Convert text/URL in memory; decrypt file/screenshot items into the bounded cache export. In presentation-safe mode, require the bounded explicit sensitive reveal before invoking either system surface. Acquire an external-interaction lease, anchor the picker to the invoking control, retain its delegate until completion, and release/clean on success, failure, cancellation, timeout, and launch reconciliation. If AirDrop is unavailable, disable it with an explanation.

- [ ] **Step 4: Implement local QR with an explicit leak preview**

Before rendering, validate URL items through `ExternalURLPolicy`, then show the exact text/URL and “Anyone who can see or scan this code can read this payload.” Require confirmation. Generate with Core Image `CIQRCodeGenerator`, correction level M, nearest-neighbor scale, and no persisted image. Close after 60 seconds. In presentation-safe mode, require the 30-second explicit sensitive reveal before rendering.

- [ ] **Step 5: Test failures, UI journeys, and zero-network behavior**

Cover missing sharing service, AirDrop unavailable, share cancel, share error, QR over 2 KiB, invalid URL, safe-mode block, timeout, app termination during share, and next-launch export cleanup. With injected sharing adapters, XCUITest covers keyboard selection of Share and AirDrop, anchored picker presentation, unavailable-state explanation, exact QR payload disclosure and confirmation, presentation-safe reveal, Escape/cancel, and focus restoration. Verify no QR path starts a listener, local server, upload, or network request.

- [ ] **Step 6: Run UI and package checks, then commit**

Run:

```bash
rtk swift test --package-path Packages/LedgeKit --filter HandoffFeatureTests
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -only-testing:LedgeUITests/HandoffFlowUITests
```

Expected: all handoff and user-flow tests pass, keyboard/focus behavior is intact, and decrypted exports are absent after every terminal outcome.

```bash
rtk git add Packages/LedgeKit LedgeUITests
rtk git commit -m "feat: add explicit local sharing actions"
```

### Task 8: Permission-Gated Screenshot Quick Capture

**Files:**
- Create: `Packages/LedgeKit/Sources/CaptureFeature/ScreenshotService.swift`
- Create: `Packages/LedgeKit/Sources/CaptureFeature/RegionSelectionController.swift`
- Create: `Packages/LedgeKit/Tests/CaptureFeatureTests/ScreenshotServiceTests.swift`
- Create: `Packages/LedgeKit/Tests/CaptureFeatureTests/RegionSelectionTests.swift`
- Create: `LedgeIntegrationTests/ScreenshotPersistenceTests.swift`
- Create: `LedgeUITests/ScreenshotCaptureUITests.swift`
- Modify: `Packages/LedgeKit/Sources/CaptureFeature/QuickCaptureView.swift`
- Modify: `LedgeApp/Resources/Info.plist`

**Interfaces:**
- Consumes: capture source snapshot, `ShelfRepository`, shell dismissal, encrypted storage, and screen descriptors.
- Produces: `ScreenshotCapturing`, region selection, screenshot captures, and handoff-compatible screenshot items.

- [ ] **Step 1: Write failing permission/cancellation tests**

```swift
@Test("Denied screenshot permission creates no file or item")
func deniedPermissionLeavesNoArtifacts() async throws {
    let repository = InMemoryShelfRepository()
    let capture = ScreenshotService(
        permission: FixedScreenCapturePermission(.denied),
        backend: FailingIfCalledScreenshotBackend(),
        repository: repository
    )

    await #expect(throws: ScreenshotError.permissionDenied) {
        try await capture.capture(.region(CGRect(x: 10, y: 20, width: 300, height: 200)))
    }
    #expect(try await repository.list(.all).isEmpty)
}

@Test("Cancel removes overlay and restores shelf state")
func canceledSelectionRestoresUI() {
    let selection = RegionSelectionReducer.reduce(.selecting(screenID: "secondary"), .cancel)
    #expect(selection == .canceled)
}
```

- [ ] **Step 2: Run screenshot tests to verify RED**

Run: `rtk swift test --package-path Packages/LedgeKit --filter CaptureFeatureTests`

Expected: FAIL because screenshot types do not exist.

- [ ] **Step 3: Implement just-in-time permission and region selection**

Call `CGPreflightScreenCaptureAccess` first and request only after a direct Screenshot action. Explain that macOS may require relaunch after approval. Create one keyboard-accessible selection overlay per screen; Escape cancels; arrows move one point, Shift-arrows move ten, Return captures. Hide Ledge before selecting/capturing. Snapshot the source app before hide only when `CaptureSourcePolicy` is `.attachApplication`; source-free screenshot tests assert the provider is never queried.

- [ ] **Step 4: Capture one frame with ScreenCaptureKit**

Use `SCShareableContent` and a display content filter excluding Ledge's running application, then `SCScreenshotManager.captureImage`. Convert the selected global rectangle into display-local pixel coordinates with backing scale, crop once off the main actor, encode lossless PNG, and pass bytes directly to encrypted storage. Never write an unencrypted intermediate screenshot.

- [ ] **Step 5: Add deterministic backend and UI coverage**

Inject a fixture image backend for CI. Test negative display coordinates, Retina/non-Retina scale, selection across a display boundary (reject with a clear message), denied/revoked permission, user cancel, capture error, Ledge exclusion, safe-mode confirmation, item expiry, and no residue after cancellation.

- [ ] **Step 6: Run and scan artifacts**

Run:

```bash
rtk swift test --package-path Packages/LedgeKit --filter CaptureFeatureTests
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -only-testing:LedgeIntegrationTests/ScreenshotPersistenceTests -only-testing:LedgeUITests/ScreenshotCaptureUITests
rtk rg --files .build/TestVaults | rtk rg '\.(png|jpg|heic)$'
```

Expected: tests pass and the file scan returns no plaintext image extensions in the vault/cache after completion.

- [ ] **Step 7: Commit screenshot capture**

```bash
rtk git add Packages/LedgeKit LedgeApp LedgeIntegrationTests LedgeUITests
rtk git commit -m "feat: add private screenshot capture"
```

### Task 9: Public Core Audio Controls and Media Capability Gate

**Files:**
- Create: `Packages/LedgeKit/Sources/AudioFeature/AudioModels.swift`
- Create: `Packages/LedgeKit/Sources/AudioFeature/CoreAudioClient.swift`
- Create: `Packages/LedgeKit/Sources/AudioFeature/AudioHardwareService.swift`
- Create: `Packages/LedgeKit/Sources/AudioFeature/AudioActivityPolicy.swift`
- Create: `Packages/LedgeKit/Sources/AudioFeature/NowPlayingProvider.swift`
- Create: `Packages/LedgeKit/Sources/AudioFeature/AudioStore.swift`
- Create: `Packages/LedgeKit/Sources/AudioFeature/AudioCardView.swift`
- Create: `Packages/LedgeKit/Tests/AudioFeatureTests/AudioHardwareServiceTests.swift`
- Create: `Packages/LedgeKit/Tests/AudioFeatureTests/AudioActivityPolicyTests.swift`
- Create: `Packages/LedgeKit/Tests/AudioFeatureTests/AudioReducerTests.swift`
- Create: `LedgeIntegrationTests/CoreAudioReadOnlyContractTests.swift`
- Create: `LedgeUITests/AudioCardUITests.swift`

**Interfaces:**
- Consumes: `AudioControlling`, `NowPlayingProviding`, shell routes, and action candidates.
- Produces: confirmed `AudioSnapshot`, capability-gated output/volume/mute commands, a deterministic session-only audio activity candidate, and an unavailable public Now Playing provider.

- [ ] **Step 1: Write failing capability and confirmation tests**

```swift
@Test("Unsupported input mute is never emulated with input volume")
func unsupportedMicMute() async throws {
    let client = FakeCoreAudioClient(
        snapshot: .fixture(inputMute: .unsupported, inputVolume: .writable(0.7))
    )
    let service = AudioHardwareService(client: client)

    await #expect(throws: AudioControlError.unsupported) {
        try await service.setInputDeviceMuted(true)
    }
    #expect(await client.inputVolumeWriteCount == 0)
}

@Test("Route switch completes only after matching listener snapshot")
func routeSwitchNeedsConfirmation() async throws {
    let client = FakeCoreAudioClient(snapshot: .fixture(defaultOutputID: "speaker"))
    let service = AudioHardwareService(client: client)
    let task = Task { try await service.setDefaultOutput("headphones") }
    await client.emit(.fixture(defaultOutputID: "headphones"))
    try await task.value
    #expect(await service.latest.defaultOutputID == "headphones")
}

@Test("Explicitly opened audio remains eligible for exactly sixty seconds")
func audioCandidateLifetime() {
    let openedAt = ContinuousClock.Instant.fixture(seconds: 100)
    let policy = AudioActivityPolicy(recentWindow: .seconds(60))

    #expect(policy.isEligible(openedAt: openedAt, now: openedAt.advanced(by: .seconds(59))))
    #expect(!policy.isEligible(openedAt: openedAt, now: openedAt.advanced(by: .seconds(60))))
}
```

- [ ] **Step 2: Run audio tests to verify RED**

Run: `rtk swift test --package-path Packages/LedgeKit --filter AudioFeatureTests`

Expected: FAIL because `AudioFeature` does not exist.

- [ ] **Step 3: Implement event-driven Core Audio capability snapshots**

Use public HAL property get/set/listener APIs. For every device and selector, check presence, scope, element, and `AudioObjectIsPropertySettable`. Represent each control as `.writable(value)`, `.readOnly(value)`, or `.unsupported`. Coalesce callbacks into newest snapshots and remove listeners on teardown.

- [ ] **Step 4: Implement confirmed writes and rollback UX**

Clamp volume to 0...1, write only to a published writable control, and wait up to two seconds for a matching listener snapshot. On timeout/device removal, refresh, keep the last confirmed state, and show a non-sensitive error. Never optimistically leave a toggle in an unconfirmed state.

- [ ] **Step 5: Implement the honest media boundary**

`UnavailableNowPlayingProvider` emits `.unavailable(reason: .noPublicCrossAppAPI)` and rejects commands. The card omits title, artwork, play/pause, next, and previous when this provider is active. No fallback may import MediaPlayer as a cross-app reader, MediaRemote, Apple Events, Accessibility, or event synthesis.

`AudioStore` records a monotonic, session-only timestamp when Audio Controls is explicitly opened from the status menu or command palette. It emits an `.available` candidate for the next 60 seconds; an in-progress output-route or mute write emits an `.immediate` candidate only until confirmation or the two-second timeout. Nothing is persisted, wall-clock changes cannot extend eligibility, and opening the general shelf does not count as opening audio.

- [ ] **Step 6: Add read-only and opt-in hardware checks**

CI may enumerate devices and query capabilities only. A local `LEDGE_AUDIO_WRITE_TESTS=1` suite may change volume/default output, captures the original state first, and restores it with `defer`. Test built-in output, wired/USB, Bluetooth, HDMI/AirPlay when available, device removal, and unsupported global input mute.

- [ ] **Step 7: Run and commit**

Run:

```bash
rtk swift test --package-path Packages/LedgeKit --filter AudioFeatureTests
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -only-testing:LedgeIntegrationTests/CoreAudioReadOnlyContractTests -only-testing:LedgeUITests/AudioCardUITests
rtk proxy ./Scripts/verify-public-apis.sh
```

Expected: tests pass; the release scan finds no private media symbol; UI labels unsupported mic control honestly.

```bash
rtk git add Packages/LedgeKit LedgeIntegrationTests LedgeUITests
rtk git commit -m "feat: add capability-aware audio controls"
```

### Task 10: Next-Action Resolver and End-to-End Shelf Composition

**Files:**
- Modify: `Packages/LedgeKit/Sources/LedgeDomain/ActionCandidate.swift`
- Create: `Packages/LedgeKit/Sources/ShellFeature/ActionResolver.swift`
- Create: `Packages/LedgeKit/Tests/ShellFeatureTests/ActionResolverTests.swift`
- Create: `LedgeApp/App/AppCoordinator.swift`
- Modify: `LedgeApp/App/AppEnvironment.swift`
- Modify: `Packages/LedgeKit/Sources/ShellFeature/ShelfRootView.swift`
- Create: `LedgeUITests/EndToEndWorkflowUITests.swift`

**Interfaces:**
- Consumes: candidate streams and commands from shell, capture, clipboard, meetings, handoff, and audio.
- Produces: the integrated one-primary/two-secondary shelf, deterministic dispatch, and complete MVP workflows.

- [ ] **Step 1: Write failing ranking and privacy tests**

```swift
@Test("Joinable meeting outranks recent tray and capture")
func meetingWinsImmediateWindow() {
    let now = Date(timeIntervalSince1970: 1_786_320_000)
    let candidates = [
        ActionCandidate.fixture(feature: .handoff, urgency: .available, dueAt: nil),
        ActionCandidate.fixture(feature: .capture, urgency: .available, dueAt: nil),
        ActionCandidate.fixture(feature: .meeting, urgency: .immediate, dueAt: now.addingTimeInterval(120))
    ]

    let result = ActionResolver().resolve(candidates, now: now, presentationSafe: false)

    #expect(result.primary?.feature == .meeting)
    #expect(result.secondary.count == 2)
}

@Test("Presentation safe removes sensitive candidates before ranking")
func safeModeFiltersBeforeRanking() {
    let sensitive = ActionCandidate.fixture(
        feature: .clipboard,
        urgency: .immediate,
        sensitivity: .sensitive
    )
    let fallback = ActionCandidate.fixture(feature: .capture, urgency: .available, sensitivity: .public)

    let result = ActionResolver().resolve([sensitive, fallback], now: .distantPast, presentationSafe: true)

    #expect(result.primary?.id == fallback.id)
    #expect(!result.all.contains(where: { $0.id == sensitive.id }))
}

@Test("Disabled Quick Capture falls back to recovery Settings")
func disabledQuickCaptureDoesNotReappear() {
    let result = ActionResolver().resolve(
        [],
        now: .distantPast,
        presentationSafe: false,
        enabledFeatures: []
    )

    #expect(result.primary?.id == FixedActionID.openSettings)
    #expect(result.all.contains(where: { $0.feature == .quickCapture }) == false)
}
```

- [ ] **Step 2: Run resolver tests to verify RED**

Run: `rtk swift test --package-path Packages/LedgeKit --filter ActionResolverTests`

Expected: FAIL because `ActionResolver` does not exist.

- [ ] **Step 3: Implement stable deterministic resolution**

Implement the order in section 2.4. Filter expired, dismissed-for-session, disabled-feature, and presentation-unsafe candidates first. Sort by urgency descending, due date ascending with `nil` last, feature priority, then UUID string. A candidate keeps the same ID for the lifetime of its underlying meeting/item/operation and uses the fixed IDs listed in section 2.4 for feature-level actions. Return at most one primary and two distinct secondary candidates. If none remain, synthesize Quick Capture only when it is enabled; otherwise return the public Open Settings action tagged `.recovery`, which is outside feature-enable filtering and cannot be disabled.

- [ ] **Step 4: Compose services at one root**

`AppEnvironment` creates concrete storage/platform services and injects protocols into `@MainActor` stores. `AppCoordinator` starts only non-permission services at launch, merges candidate streams with newest-value buffering, dispatches typed `ShelfCommand` cases, and keeps one authoritative presentation-safe state. Feature modules do not import one another.

- [ ] **Step 5: Build the focused shelf view**

Peek renders the primary action plus at most two icon-and-label secondaries. Expanded state renders only the selected feature. Remove persistent feature tabs. Every successful one-shot action dismisses; long imports remain visible only while progress needs attention. Errors offer Retry/Settings/Dismiss rather than opening a dashboard.

- [ ] **Step 6: Add complete local-first journeys**

XCUITest with Debug-only injected platform fakes covers: launch -> hotkey -> note -> dismiss; copied text -> search -> copy -> dismiss; meeting becomes immediate -> Join -> dismiss; file drop -> move-from-shelf; screenshot -> Share; audio route switch; mirrored display redaction; denied Calendar/Screen Recording while unrelated flows keep working. A Release-build test supplies the same fixture arguments and asserts they are ignored.

- [ ] **Step 7: Run all functional suites**

Run:

```bash
rtk swift test --package-path Packages/LedgeKit
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -only-testing:LedgeUITests/EndToEndWorkflowUITests
```

Expected: all module tests and end-to-end journeys pass; peek never renders more than three actions.

- [ ] **Step 8: Commit integration**

```bash
rtk git add Packages/LedgeKit LedgeApp LedgeUITests
rtk git commit -m "feat: compose contextual next-action shelf"
```

### Task 11: Settings, Just-in-Time Onboarding, Accessibility, and Recovery

**Files:**
- Create: `LedgeApp/Settings/SettingsView.swift`
- Create: `LedgeApp/Settings/GeneralSettingsView.swift`
- Create: `LedgeApp/Settings/PrivacySettingsView.swift`
- Create: `LedgeApp/Settings/StorageSettingsView.swift`
- Create: `LedgeApp/Settings/ShortcutSettingsView.swift`
- Create: `LedgeApp/Settings/DiagnosticsView.swift`
- Create: `LedgeApp/App/PermissionCenter.swift`
- Create: `LedgeApp/Settings/LoginItemController.swift`
- Create: `Packages/LedgeKit/Sources/ShellFeature/AppCapabilityState.swift`
- Create: `Packages/LedgeKit/Tests/ShellFeatureTests/PermissionPresentationTests.swift`
- Create: `LedgeUITests/OnboardingUITests.swift`
- Create: `LedgeUITests/AccessibilityUITests.swift`
- Create: `LedgeUITests/RecoverySurfaceUITests.swift`

**Interfaces:**
- Consumes: all feature settings, permission states, hotkey registration, storage reports, `SMAppService.mainApp`, and status recovery.
- Produces: nonblocking onboarding, permission recovery, launch-at-login opt-in, data purge, redacted diagnostics, and accessibility acceptance evidence.

- [ ] **Step 1: Write failing permission-isolation and recovery tests**

```swift
@Test("Denied calendar does not disable capture or clipboard")
func permissionIsolation() {
    let state = AppCapabilityState(
        calendar: .denied,
        screenCapture: .notDetermined,
        pasteboard: .allowed
    )
    #expect(state.isEnabled(.meetings) == false)
    #expect(state.isEnabled(.quickCapture) == true)
    #expect(state.isEnabled(.clipboard) == true)
}

@Test("Recovery remains when every feature service fails")
func recoverySurvivesServiceFailure() async {
    let app = AppCoordinator(environment: .allServicesFailing)
    await app.start()
    #expect(app.statusMenuState.canOpenSettings)
    #expect(app.statusMenuState.canQuit)
}
```

- [ ] **Step 2: Run focused tests to verify RED**

Run: `rtk swift test --package-path Packages/LedgeKit --filter PermissionPresentationTests`

Expected: FAIL because capability presentation has not been implemented.

- [ ] **Step 3: Implement one-page onboarding without a setup gate**

First launch shows the shelf hotkey, status-item recovery, local-only statement, and feature toggles. It requests no permission. Enabling Meetings opens a preflight explanation and then EventKit consent. Invoking Screenshot opens its explanation and then Screen Recording consent. Enabling Clipboard explains pasteboard prompts, best-effort exclusions, pause, retention, and Clear All before starting the monitor.

Onboarding is dismissible and never blocks Settings, Quit, or quick capture. Store completion as a non-sensitive preference; a corrupt/missing preference simply shows onboarding again without resetting user data.

- [ ] **Step 4: Implement recovery and storage controls**

Settings exposes current hotkeys and registration conflicts, reset panel position, permission status plus “Open System Settings,” the “Attach source app” capture policy, pause clipboard, exclusion bundle IDs, retention choices, vault usage, Clear Expired, Delete Clipboard History, Delete All Ledge Data, and local diagnostics export. Destructive actions name exact data classes and require confirmation. “Delete All” stops feature services and operations, clears decrypted memory, deletes the Keychain master key first, then removes the vault, SQLite database/WAL/SHM, export cache, and all Ledge-owned preferences before recreating a fresh store; macOS-managed permission decisions remain in System Settings. If file cleanup is interrupted, remaining payloads are unreadable and launch reconciliation offers cleanup without generating a replacement key over them. Never label this physical secure erase. Diagnostics include versions, capability booleans, counts, timings, and error categories only.

- [ ] **Step 5: Implement user-controlled launch at login**

On toggle, call `SMAppService.mainApp.register()` or `.unregister()`, present `.requiresApproval` with `SMAppService.openSystemSettingsLoginItems()`, and keep the app functional if registration fails. Never install or register a helper executable.

- [ ] **Step 6: Add accessibility behavior to every view**

Use native `Button`, `Toggle`, `Slider`, `List`, and `TextField` controls where possible. Add labels/values/hints for icon-only actions and dynamic states, logical sort priorities, visible keyboard focus, and polite announcements for completed imports/route changes. Respect Reduce Motion, Reduce Transparency, Increase Contrast, and dynamic type. A modal contains focus, Escape closes it, and dismissal restores the trigger/prior app.

- [ ] **Step 7: Add UI and accessibility audits**

Test onboarding dismissal/relaunch, every permission denial, hotkey conflict, offscreen reset, corrupt data quarantine, keychain unavailable, clipboard pause, each purge, login-item denial, light/dark/high-contrast, Reduce Motion/Transparency, 200% text, VoiceOver element names/order, keyboard-only completion, and 44-point primary targets.

- [ ] **Step 8: Run and commit**

Run:

```bash
rtk swift test --package-path Packages/LedgeKit
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -only-testing:LedgeUITests/OnboardingUITests -only-testing:LedgeUITests/AccessibilityUITests -only-testing:LedgeUITests/RecoverySurfaceUITests
```

Expected: tests pass; no denial/hotkey/storage failure traps the app in onboarding or removes Settings/Quit.

```bash
rtk git add LedgeApp Packages/LedgeKit LedgeUITests
rtk git commit -m "feat: harden onboarding and recovery"
```

### Task 12: Coverage, Energy, Security, Hardware Matrix, and Store Candidate

**Files:**
- Create: `Scripts/check-coverage.sh`
- Create: `Scripts/check-third-party-licenses.sh`
- Create: `Scripts/measure-idle-energy.sh`
- Create: `LedgePerformanceTests/ShellLatencyPerformanceTests.swift`
- Create: `LedgePerformanceTests/ClipboardSearchPerformanceTests.swift`
- Create: `LedgePerformanceTests/FileVaultImportPerformanceTests.swift`
- Create: `LedgePerformanceTests/LaunchPerformanceTests.swift`
- Create: `docs/testing/hardware-matrix.md`
- Create: `docs/testing/app-review-notes.md`
- Modify: `docs/compliance/source-provenance.md`
- Modify: `.github/workflows/ci.yml`
- Modify: `Scripts/verify-public-apis.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: the complete integrated MVP from Tasks 0-11.
- Produces: reproducible CI, coverage and performance evidence, public-API/security scans, hardware results, App Review notes, and a release-candidate gate.

- [ ] **Step 1: Write failing performance and bounded-cache tests**

```swift
func testWarmRevealPerformance() throws {
    let coordinator = ShellPerformanceFixture.warmed()
    measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
        coordinator.revealAndRenderOneFrame()
        coordinator.dismiss()
    }
}

@Test("Clipboard search cache never exceeds configured bounds")
func searchCacheBound() async throws {
    let search = ClipboardSearch(capacity: 500)
    await search.replace(with: (0..<750).map(ClipboardEntry.fixture))
    #expect(await search.cachedEntryCount == 500)
}
```

- [ ] **Step 2: Run performance/coverage commands and record the initial failures**

Run:

```bash
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -destination 'platform=macOS' -enableCodeCoverage YES -resultBundlePath .build/LedgeTests.xcresult
rtk proxy ./Scripts/check-coverage.sh .build/LedgeTests.xcresult
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -destination 'platform=macOS' -only-testing:LedgePerformanceTests
```

Expected: the new tests or coverage gate fail until caches, instrumentation, and missing branches are completed.

- [ ] **Step 3: Implement coverage reporting and close real gaps**

`check-coverage.sh` reads the `.xcresult`, excludes Apple/generated code and test targets, enforces 80% per first-party module, and enforces 90% for geometry, URL policy, clipboard policy, crypto, expiry, and file transactions. Add behavior tests for uncovered branches; do not exclude difficult first-party files or add empty assertions.

- [ ] **Step 4: Add signposts and measure resource budgets**

Add content-free `OSSignposter` intervals for launch-to-hotkey-ready, reveal-to-first-frame, clipboard change-to-snapshot, route switch, import, export, and search. `measure-idle-energy.sh` launches a signed Release build with a clean test container, records its PID, samples `ps` for CPU/RSS, `powermetrics` or Instruments Energy Log for wakeups, and `nettop -p <pid> -L 1 -J bytes_in,bytes_out` for process network bytes for ten minutes with clipboard off and on. It records machine/OS/build metadata, rejects any increase in process network bytes, and fails the numeric gates in section 7. If `powermetrics` cannot run without elevation, the script reports that energy evidence is incomplete and the release hardware gate must run it interactively; it never silently substitutes an estimate.

- [ ] **Step 5: Complete the manual hardware/display matrix**

Record pass/fail plus evidence for: notched internal screen; notchless Mac; one, two, and three displays; menu bar on each display; negative coordinates; Retina/non-Retina; extended and mirrored; hot unplug while peek/expanded/importing; Spaces; Stage Manager; full-screen app with menu bar shown/hidden; Reduce Motion/Transparency; sleep/wake; lock/unlock; time-zone/clock jump; Calendar/Screen Recording/pasteboard denial and revocation; built-in/USB/Bluetooth/HDMI audio; unsupported input mute; disk full; Keychain locked; and 1 GiB vault boundary.

- [ ] **Step 6: Run privacy and security release checks**

Verify:

- Archive entitlements exactly match section 3.2 and omit network/audio-input/automation/accessibility.
- No private frameworks/symbols, extra executables, unsigned nested code, undeclared third-party dependency, or AGPL-licensed source/assets. `source-provenance.md` records the origin and SPDX license for every non-original snippet/asset; the initial expected state is “none.” `check-third-party-licenses.sh` rejects undeclared package dependencies, forbidden license identifiers/notices in source and asset paths, and provenance drift. This automated scan is defense in depth, not proof of independent authorship: a release reviewer must also inspect the implementation diff and provenance register, and implementation agents must use this plan plus official Apple documentation rather than Sapphire source as a coding reference.
- Release symbol/string scans find no `LEDGE_UITESTING`, fake-service registry, fixture payload, test secret, or launch-argument injection path.
- URL scheme/host, QR size, filenames, symlink, SQLite, encrypted envelope, and drag-item inputs fail closed.
- Normal, error, diagnostics, crash, and signpost outputs contain no seeded secret fixture.
- A network observer sees zero outbound connections through every flow.
- Decrypted share exports are absent after completion, timeout, crash recovery, and next launch.
- Denied/revoked permissions stop the related service and clear sensitive in-memory snapshots.

- [ ] **Step 7: Run the actual release-equivalent suite**

Run:

```bash
rtk swift test --package-path Packages/LedgeKit
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -destination 'platform=macOS' -enableCodeCoverage YES -resultBundlePath .build/LedgeTests.xcresult
rtk proxy ./Scripts/check-coverage.sh .build/LedgeTests.xcresult
rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -destination 'platform=macOS' -only-testing:LedgePerformanceTests
rtk xcodebuild archive -project Ledge.xcodeproj -scheme Ledge -configuration Release -archivePath .build/Ledge.xcarchive
rtk proxy ./Scripts/verify-public-apis.sh .build/Ledge.xcarchive
rtk proxy ./Scripts/check-third-party-licenses.sh
rtk proxy ./Scripts/measure-idle-energy.sh .build/Ledge.xcarchive
rtk git diff --check
```

Expected: all unit, integration, UI/E2E, performance, coverage, archive, public-API, privacy, energy, and whitespace gates pass. Do not claim release readiness from package tests alone.

- [ ] **Step 8: Write App Review notes and README scope**

Document each permission's direct user action, the absence of network/analytics/helpers/private APIs, the public Core Audio capability model, no universal Now Playing claim, presentation-safe redaction semantics, clipboard attribution limitation, data retention/deletion wording, and reviewer steps for status-menu/hotkey recovery. README lists exactly the six MVP modules and explicit scope cuts.

- [ ] **Step 9: Commit the verified release gates**

```bash
rtk git add Scripts LedgePerformanceTests docs/testing docs/compliance .github README.md
rtk git commit -m "test: add macOS release quality gates"
```

## 2. Product and Public-API Decisions

### 2.1 Honest MVP contract

| Requested capability | MVP contract | Public-API boundary |
|---|---|---|
| Adaptive shell | Full scope: notch, notchless, multiple external displays, hover, hotkey, recovery, full-screen suppression | Use dynamic `NSScreen` geometry; never infer notch shape from model names |
| Now Playing + audio | Ship output device, output volume/mute, and capability-probed input-device mute; hide unsupported controls | Public MediaPlayer APIs describe media played by this app, not arbitrary apps; universal metadata/transport is out of scope |
| Next meeting | Full scope after explicit EventKit consent | Reading events requires full Calendar access; keep event data in memory |
| Handoff tray | Files, text, URLs, screenshots, explicit copy/move-from-shelf, Share, AirDrop, QR, expiry | File destinations must come from user-selected access; QR contains raw text/URL after confirmation |
| Quick capture | Note, task, link, screenshot, source app/timestamp, and an optional explicitly supplied HTTP(S) context URL | Automatic source window titles, selected text, and browser URLs require broader automation/accessibility; do not collect them |
| Clipboard shelf | Opt-in text/URL history, search, favorites, keyboard control, retention, pause, clear, per-app exclusion policy | `NSPasteboard` does not expose trustworthy source-app identity; exclusions use the frontmost app at detection and are explicitly best-effort |

Do not market feature 2 as universal Now Playing. `MPNowPlayingInfoCenter` lets an app publish information for media it plays, and `MPRemoteCommandCenter` lets that media app receive commands. Ledge must not substitute private MediaRemote APIs, arbitrary Apple Events, or synthesized media keys. If cross-app metadata and transport later become non-negotiable, treat that as a separate product/distribution decision rather than quietly weakening this boundary.

For microphone controls, probe `kAudioDevicePropertyMute` on the default input scope and verify that the property is present and settable. A process-scoped input mute does not mute other apps and must never be labeled system mic mute. If no writable device control exists, render “Not supported by this input device” and keep the control disabled.

### 2.2 What “presentation safe” means

Presentation-safe mode redacts Ledge content; it does not claim to evade screen capture:

- Replace meeting title and agenda with “Meeting in N minutes,” while retaining Join.
- Replace tray, capture, and clipboard previews with counts and generic kinds.
- Suppress automatic hover expansion and require an explicit hotkey or click.
- Enable automatically when Quartz reports display mirroring. A setting may extend this to every external display.
- Allow a 30-second explicit reveal on the current display, with a visible “Sensitive content shown” state.
- Before opening an Apple-owned Save, Share, or AirDrop surface, warn that Ledge cannot redact that system UI; require explicit confirmation and restore Ledge's own redaction when the external-interaction lease ends.
- Never use `NSWindow.SharingType.none` as protection; Apple documents it as a legacy value that should not be used to hide content from capture.

### 2.3 Interaction model

The shell state machine has four modes:

```text
hidden
  -> peek             hover dwell or shelf hotkey
  -> commandPalette   quick-capture/search hotkey

peek
  -> expanded         click, Return, or arrow navigation
  -> hidden           pointer exit, timeout, Escape, Space/display change

expanded
  -> hidden           action completes, Escape, outside click
  -> commandPalette   explicit capture/search command

commandPalette
  -> hidden           submit, cancel, Escape, focus restoration
```

- Hover uses a tiny per-display trigger `NSPanel` with tracking areas; there is no whole-screen mouse polling or display link.
- On a notched screen, position the trigger immediately below the camera-housing safe-area gap, never over inferred hardware coordinates.
- On notchless/external screens, top-center hover is off by default; hotkey and status item always work, and the user can enable a 4-point trigger strip per display.
- Automatic hover is suppressed when full-screen status is unknown or likely. The shelf hotkey may show a five-second compact peek in the full-screen Space; an explicitly invoked capture/search editor remains only until submit, cancel, Escape, or key-window loss.
- Hover opens a mouse-safe peek without activation. A hotkey may make the nonactivating panel key for text input; dismissing restores the prior workflow.
- Only one shelf expands at a time. Hotkey placement uses the screen containing the pointer, then the menu-bar screen, then `NSScreen.main`.

### 2.4 Deterministic next-action resolver

Every feature contributes zero or more immutable candidates. The resolver uses no model, network, or content profiling.

```swift
public struct ActionCandidate: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let feature: FeatureID
    public let title: String
    public let subtitle: String?
    public let dueAt: Date?
    public let urgency: ActionUrgency
    public let sensitivity: Sensitivity
    public let command: ShelfCommand
    public let expiresAt: Date?
}

public enum ActionUrgency: Int, Sendable, Codable {
    case background = 0
    case available = 10
    case soon = 20
    case immediate = 30
}

public enum FixedActionID {
    public static let quickCapture = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    public static let openSettings = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    public static let audioControls = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    public static let clipboardSearch = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
}
```

Ranking order, with stable ID as the final tie-breaker:

1. A joinable meeting from five minutes before start through ten minutes after start.
2. An active user operation that needs a decision, such as choosing an export destination.
3. A meeting beginning within 30 minutes.
4. The most recent unhandled quick capture or newly imported tray item.
5. An audio candidate emitted for 60 seconds after the user explicitly opens Audio Controls, or only for the duration of a confirmed-write operation in progress.
6. “Quick capture” as the fallback when enabled; otherwise the always-available, content-free Open Settings recovery action.

Presentation-safe mode filters sensitive candidates before ranking. Dismissal is session-only and does not modify source data.

### 2.5 Explicit scope cuts

- No universal cross-app Now Playing metadata or playback transport.
- No global mic-mute promise; only a writable input-device mute control may be shown.
- No arbitrary selected-text, window-title, or browser-tab URL scraping.
- No automatic detection of Zoom/Teams/Meet screen sharing and no claim that Ledge can hide from a capture.
- No folder/package imports, source-file deletion, synthetic paste into another app, OCR, screenshot editor, screen video, or audio recording.
- No Google/Microsoft calendar OAuth, calendar editing, or attendee ingestion; EventKit calendars only.
- No clipboard images/files/rich text and no claim that exclusions or secret heuristics can catch every credential.
- No feature 7-10 launcher, focus, notification, integration, widget, or plugin infrastructure until the MVP passes reliability and energy gates.
- No weather, stocks, face unlock, AI screen sharing, Android/Nearby Share, per-app EQ, or window snapping.

## 3. System Architecture

```mermaid
flowchart TD
    App["LedgeApp composition root"] --> Shell["AppKit shell and status recovery"]
    App --> Stores["MainActor observable feature stores"]
    Stores --> Resolver["Deterministic ActionResolver"]
    Resolver --> Shell
    Stores --> Domain["Immutable LedgeDomain values and protocols"]
    Domain --> Storage["ShelfStore actor plus encrypted blobs"]
    Domain --> Platform["Platform service actors"]
    Platform --> EventKit["EventKit"]
    Platform --> Audio["Core Audio HAL"]
    Platform --> Capture["ScreenCaptureKit"]
    Platform --> Pasteboard["NSPasteboard"]
    Storage --> Keychain["Keychain master key"]
    Storage --> SQLite["SQLite metadata and operation journal"]
    Storage --> Vault["Chunked AES-GCM payload vault"]
```

### 3.1 Process and concurrency ownership

| Owner | Isolation | Responsibility |
|---|---|---|
| `AppCoordinator` | `@MainActor @Observable` | Composition, feature enablement, routes, permission summaries |
| `ShellPanelCoordinator` | `@MainActor` | AppKit panels, status item, focus restoration, screen/Space changes |
| Feature stores | `@MainActor @Observable` | Convert service snapshots into small render state and candidates |
| `ShelfStore` | actor | SQLite migrations, transactions, metadata, decrypted bounded search cache |
| `EncryptedPayloadVault` | actor | Chunked encryption, atomic imports/exports, recovery, cleanup |
| `MeetingService` | actor | Own one long-lived `EKEventStore`; emit `MeetingSnapshot` DTOs |
| `AudioHardwareService` | actor | Core Audio property listeners, capability snapshots, confirmed writes |
| `ClipboardMonitor` | actor | Adaptive `changeCount` polling, exclusion checks, dedupe, retention |
| `ExpiryScheduler` | actor | Sleep until nearest deadline; recalculate on wake and time changes |

Framework callbacks enqueue a `Task` into their owner and never mutate SwiftUI state directly. Snapshot streams use `AsyncStream(bufferingPolicy: .bufferingNewest(1))` so rapid screen/audio/calendar changes coalesce. Detached tasks and a stringly typed global event bus are prohibited. On session lock or protected-data unavailability, clear decrypted search, preview, QR, meeting, and export caches before suspending monitors.

`ScreenDescriptor` is a domain value containing Core Graphics rectangles plus a custom `ScreenInsets: Sendable, Equatable`; the AppKit adapter copies values from `NSScreen`. Do not carry `NSScreen` or other mutable AppKit objects across actor boundaries.

### 3.2 Entitlements and purpose strings

`LedgeApp/Resources/Ledge.entitlements` contains only:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.personal-information.calendars</key>
<true/>
```

`Info.plist` contains these exact purpose strings:

- `NSCalendarsFullAccessUsageDescription`: “Ledge reads upcoming events to show your next meeting and join link. Event details stay on this Mac.”
- `NSScreenCaptureUsageDescription`: “Ledge captures only the screen region you select and stores it locally.”

It omits network client, audio input, Accessibility, Automation, Contacts, Bluetooth, and persistent content capture entitlements. `LSUIElement` is `true`; the app supplies a status item and explicit Settings window.

Use `SMAppService.mainApp` only when the user turns on “Launch at Login.” Do not register it during onboarding.

### 3.3 Local data model

Domain records stay typed and plaintext only in process memory:

```swift
public enum ShelfItemKind: String, Codable, Sendable {
    case note, task, link, screenshot, clipboardText, clipboardURL
    case trayFile, trayText, trayURL
}

public struct SourceContext: Codable, Sendable, Equatable {
    public let bundleIdentifier: String?
    public let applicationName: String?
    public let explicitURL: URL?
    public let capturedAt: Date

    public init(
        bundleIdentifier: String?,
        applicationName: String?,
        explicitURL: URL? = nil,
        capturedAt: Date
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.explicitURL = explicitURL
        self.capturedAt = capturedAt
    }
}

public struct ShelfItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let kind: ShelfItemKind
    public let content: ShelfContent
    public let source: SourceContext?
    public let createdAt: Date
    public let expiresAt: Date?
    public let isFavorite: Bool
}

public enum ShelfContent: Sendable, Equatable {
    case text(String)
    case url(URL)
    case task(title: String, isComplete: Bool)
    case binary(BinaryDescriptor)
}
```

SQLite stores only non-content metadata:

```sql
CREATE TABLE shelf_item (
    id TEXT PRIMARY KEY NOT NULL,
    kind TEXT NOT NULL,
    created_at REAL NOT NULL,
    expires_at REAL,
    is_favorite INTEGER NOT NULL CHECK (is_favorite IN (0, 1)),
    state TEXT NOT NULL CHECK (state IN ('importing', 'ready', 'deleting')),
    payload_path TEXT NOT NULL UNIQUE,
    payload_bytes INTEGER NOT NULL CHECK (payload_bytes >= 0),
    keyed_digest BLOB NOT NULL
);

CREATE TABLE storage_operation (
    id TEXT PRIMARY KEY NOT NULL,
    item_id TEXT NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('import', 'export', 'delete')),
    stage TEXT NOT NULL,
    created_at REAL NOT NULL,
    FOREIGN KEY (item_id) REFERENCES shelf_item(id) ON DELETE CASCADE
);
```

Set WAL mode, foreign keys, a five-second busy timeout, and `PRAGMA user_version = 1`. Store display names, filenames, source context, text, URLs, task state, screenshot bytes, and file bytes inside the encrypted payload, not SQLite.

### 3.4 Encryption and file lifecycle

- Generate one 256-bit random master key and store it with Keychain Services using `kSecUseDataProtectionKeychain = true`, `kSecAttrSynchronizable = false`, and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Derive separate encryption and keyed-digest keys with HKDF-SHA256 and fixed domain labels.
- Payload format: `LEDGE1` magic, format version, item UUID, kind, content length, 1 MiB chunk size, and a random eight-byte nonce prefix form a canonical header. Authenticate that header with an AES-GCM empty-plaintext manifest record using nonce suffix `0xFFFFFFFF`. Seal each data chunk independently with nonce prefix plus its big-endian 32-bit index; its AAD is the canonical header plus record kind, index, and actual plaintext chunk length. Reserve `0xFFFFFFFF` for the manifest, reject duplicate/out-of-order indexes and non-final short chunks, and enforce the configured item/vault size bounds before allocation. This authenticates even an empty payload and prevents header, truncation, reordering, or length-confusion attacks.
- Create Ledge-owned data directories with mode `0700`, reject a symlink/non-directory at any expected container component, and write into `Application Support/<bundle-id>/Vault/.incoming/<operation-id>`. Synchronize the file, atomically rename into `Vault/<item-id>.ledge`, fsync the destination directory, then mark the SQLite row ready.
- Mark the SQLite, vault, incoming, and export directories excluded from backup. Ledge is a temporary local workflow surface, not a backup system; explain this in storage settings and never imply pinned items are recoverable after device loss.
- On launch, remove stale incoming files, reconcile `importing`/`deleting` operations idempotently, quarantine corrupt encrypted payloads, and report counts without content.
- Decryption for an explicit Share/AirDrop/export creates a backup-excluded `Caches/Exports/<operation-id>/` directory with mode `0700` and, only when the receiving system UI needs a file URL, a mode-`0600` file using the sanitized original display name. Show that name before export, never reuse the source path, create no thumbnail/preview copy, and remove the operation directory on delegate completion, cancellation, ten-minute timeout, and next launch.
- Deletion marks the row `.deleting` so queries hide it immediately, records the operation, removes the blob idempotently, and only then deletes the row. Launch reconciliation finishes any interrupted stage. Product copy must say “removed from Ledge,” not “securely erased”; APFS, SSD behavior, snapshots, and backups prevent a physical-overwrite guarantee.
- If the Keychain key is unavailable, pause sensitive reads/writes and offer either retry or deletion of unreadable local data. Never fall back to plaintext.

### 3.5 Retention and limits

| Data class | Default | Limit | Favorite/pin behavior |
|---|---:|---:|---|
| Handoff tray | 24 hours | 100 items, 1 GiB total vault budget | User may choose 1 hour, 1 day, 7 days, or keep |
| Clipboard | 7 days | 500 entries, 64 KiB each | Up to 100 favorites do not expire |
| Notes/links/tasks | 30 days | 500 open captures | Pinned items do not expire; completed tasks expire after 7 days |
| Screenshots | 24 hours | Included in 1 GiB vault budget | Pinned screenshots do not expire |
| Calendar | Memory only | Next 24 hours | Never persisted |
| QR render | Memory only | 2 KiB UTF-8 payload | Destroy when panel closes or after 60 seconds |

Source context (application and explicit URL) has a separate seven-day maximum and is removed by rewriting the encrypted payload even when an item is pinned/favorited; “Remove all context” stores none, and `.neverAttach` prevents the app lookup from the outset. Expiry uses one next-deadline task and also runs on launch, wake, time-zone/clock change, and shelf reveal. It does not promise exact cleanup while the app is quit.

### 3.6 Local feature rollout

Flags are local typed preferences, not a remote service:

| Flag | Release default |
|---|---|
| `shell.enabled` | on |
| `shell.notchedHover` | on |
| `shell.notchlessHover` | off |
| `audio.deviceControls` | on, with unsupported controls hidden/disabled |
| `meetings.enabled` | off until the user enables and authorizes it |
| `handoff.enabled` | on |
| `quickCapture.enabled` | on |
| `quickCapture.attachSourceApp` | on, with per-capture Remove and a persistent privacy switch |
| `screenshot.enabled` | off until first explicit use |
| `clipboard.enabled` | off until explicit privacy onboarding |
| `presentationSafe.mirroredDisplays` | on |
| `presentationSafe.allExternalDisplays` | off |

Disabling a feature stops its service and candidates but leaves its encrypted data until the person chooses the matching purge action. There is no hidden configuration path for integrations, plugins, networking, or private media APIs.

## 4. Platform Boundaries by Feature

### Adaptive shell

- Compute placement from `frame`, `visibleFrame`, `safeAreaInsets`, `auxiliaryTopLeftArea`, and `auxiliaryTopRightArea`.
- Observe `NSApplication.didChangeScreenParametersNotification`, `NSWorkspace.activeSpaceDidChangeNotification`, wake/sleep, and menu-bar ownership changes.
- Use a borderless `.nonactivatingPanel` with `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.transient`, and `.ignoresCycle` for explicit reveal. Auto-hover panels opt out of full-screen Spaces.
- Treat a target as full-screen when either the menu bar is hidden or the frontmost app's topmost layer-zero window from public Quartz Window Services covers at least 98% of that screen. If window bounds are unavailable, ambiguous, or span screens, suppress auto-hover. This heuristic never grants automatic reveal; the hotkey remains available.
- Close before recalculating after a screen/Space change; never animate from stale cross-display coordinates.
- The status menu contains Open Shelf, Quick Capture, Search Clipboard, Audio Controls, Pause Clipboard, Presentation Safe, Settings, Reset Shelf Position, and Quit. The command palette exposes the same Audio Controls route without making audio a permanent tab.

### Audio

- Enumerate devices and listen for changes with public Core Audio HAL APIs; do not poll.
- Expose default output switch, output scalar volume/mute, and input-device mute only when the exact property is present and settable.
- Confirm writes from subsequent property-listener snapshots; show a progress state and time out after two seconds.
- If an output disappears mid-switch, refresh and retain the last confirmed state.
- Do not capture any audio samples and do not add an audio-input entitlement.
- Keep `NowPlayingProviding` as an interface with an `UnavailableNowPlayingProvider` so the UI hides metadata/transport without private fallbacks.

### Next meeting

- Ask for EventKit full access only after Meetings is enabled; denial leaves the rest of Ledge functional.
- Keep one `EKEventStore`, refetch on its change notification, wake, time-zone change, and day rollover.
- Fetch now through 24 hours; exclude declined, canceled, all-day, and events ending more than ten minutes ago.
- Join URL precedence is `event.url`, location, then notes. The initial known-provider suffix set is `meet.google.com`, `zoom.us`, `teams.microsoft.com`, `teams.live.com`, and `webex.com`, with subdomains matched only on a label boundary. Accept an unknown HTTPS host from `event.url` only after confirmation; location/notes scanning selects known-provider URLs only. Reject `file`, `javascript`, `data`, embedded credentials, control characters, deceptive suffixes such as `zoom.us.example.com`, and invalid IDNs.
- Render at minute granularity while hidden and second granularity only while visible and within five minutes of start.
- Keep title/agenda/URL only in memory and clear immediately when permission is revoked.

### Handoff tray

- Accept multiple regular files, plain text, HTTP(S) URLs, and Ledge screenshots. Reject directories, symlinks, device nodes, sockets, path traversal, and more than 100 items per drop.
- Import into UUID-derived vault paths; user filenames never become path components.
- Preflight available capacity and the 1 GiB vault budget before streaming import.
- “Copy out” keeps the tray item. “Move from shelf” exports, verifies byte count and digest, then removes the managed shelf copy; it never deletes the user's original source.
- Get destinations through `NSSavePanel`, folder selection, or drag-out file promises.
- Use `NSSharingServicePicker` and `.sendViaAirDrop`. Use Core Image QR generation for text/URL only after showing the exact payload and an explicit confirmation.

### Quick capture

- Default shelf hotkey: Control-Option-Space. Default capture hotkey: Control-Option-N. Both are user-configurable.
- Wrap the public legacy `RegisterEventHotKey` API behind `HotKeyRegistering`; do not monitor arbitrary key events. A registration conflict produces a recoverable Settings state.
- When “Attach source app” is enabled, snapshot `NSWorkspace.frontmostApplication` before the panel becomes key. When disabled, do not query it; the capture panel may also discard an already-snapshotted source before save.
- Prefixes: `n ` note, `t ` task, `l ` link; Tab cycles kind, Command-Return saves, Escape cancels.
- A link's URL is its context automatically. Notes, tasks, and screenshots may accept one user-entered or dropped HTTP(S) context URL through Command-L; arbitrary browser-tab URL/window-title discovery and programmatic pasteboard reads are deferred.
- Screenshot capture uses ScreenCaptureKit only after an explicit command and permission. Hide Ledge, exclude its process in the content filter, let the person select a region, and persist only after confirmation.

### Clipboard

- History is off by default. Enabling it explains retention, exclusions, the source-attribution limitation, and macOS pasteboard permission behavior before the first read.
- On macOS 15.4 and later, map `accessBehavior` behind an availability guard. Background history runs only for `.alwaysAllow`; `.default`, `.ask`, and `.alwaysDeny` remain paused except for a single explicit Grant Access probe. On 15.0-15.3, report `.legacyUnavailable` and keep the same explicit Ledge opt-in/pause controls rather than inferring permission from empty clipboard content.
- Poll `changeCount` once per second while enabled/unlocked, once every two seconds in Low Power Mode, and never while asleep, session-locked, or paused.
- When the foreground app is excluded, inspect only `changeCount`, advance the watermark, and never read types or content.
- If app activation changes around a detected change and either adjacent app is excluded or unknown, fail closed.
- Capture only plain text and HTTP(S) URLs up to 64 KiB. Skip files, images, rich text, empty values, concealed/transient convention types, and unsupported types.
- Ship `SensitiveApps.json` with schema version 1 and these initial editable bundle IDs: `com.apple.Passwords`, `com.apple.keychainaccess`, `com.1password.1password`, `com.bitwarden.desktop`, `org.keepassxc.keepassxc`, `com.markmcguill.strongbox.mac`, `in.sinew.Enpass-Desktop`, and `com.dashlane.Dashlane`. Validate this resource in tests, ignore entries for apps not installed, and let people add/remove identifiers. Label the entire mechanism best-effort because pasteboard items do not carry a trusted originating bundle ID.
- Apply exclusions before encryption, persistence, indexing, thumbnails, metrics, or logs.
- Build a bounded decrypted search index in actor memory; never persist plaintext FTS terms.
- Record Ledge's own pasteboard `changeCount` after copying so the monitor does not ingest its own write.

## 5. File and Module Map

```text
Config/
  Base.xcconfig
  Debug.xcconfig
  Release.xcconfig
Ledge.xcodeproj/
  project.pbxproj
  xcshareddata/xcschemes/Ledge.xcscheme
LedgeApp/
  App/LedgeApp.swift
  App/AppDelegate.swift
  App/AppEnvironment.swift
  App/AppCoordinator.swift
  App/PermissionCenter.swift
  Resources/Info.plist
  Resources/Ledge.entitlements
  Resources/Assets.xcassets/
  Resources/SensitiveApps.json
  Settings/SettingsView.swift
  Settings/GeneralSettingsView.swift
  Settings/PrivacySettingsView.swift
  Settings/StorageSettingsView.swift
  Settings/ShortcutSettingsView.swift
  Settings/DiagnosticsView.swift
  Settings/LoginItemController.swift
Packages/LedgeKit/
  Package.swift
  Sources/LedgeDomain/
    ActionCandidate.swift
    ExternalURLPolicy.swift
    ShelfItem.swift
    ShelfRepository.swift
    PlatformProtocols.swift
  Sources/LedgeStorage/
    SQLiteShelfStore.swift
    SQLiteConnection.swift
    ShelfMigration.swift
    KeychainMasterKeyStore.swift
    EncryptedPayloadVault.swift
    PayloadEnvelope.swift
    ExpiryScheduler.swift
  Sources/ShellFeature/
    AppCapabilityState.swift
    ShellState.swift
    ShellReducer.swift
    ScreenDescriptor.swift
    ShelfGeometryResolver.swift
    ShellPanel.swift
    ShellPanelCoordinator.swift
    HoverTriggerPanel.swift
    CarbonHotKeyRegistrar.swift
    StatusItemController.swift
    ActionResolver.swift
    ShelfRootView.swift
  Sources/AudioFeature/
    AudioModels.swift
    AudioHardwareService.swift
    AudioActivityPolicy.swift
    CoreAudioClient.swift
    AudioStore.swift
    AudioCardView.swift
    NowPlayingProvider.swift
  Sources/MeetingFeature/
    MeetingModels.swift
    EventKitMeetingService.swift
    JoinURLParser.swift
    MeetingSelector.swift
    PresentationRedactor.swift
    MeetingStore.swift
    MeetingCardView.swift
  Sources/HandoffFeature/
    IncomingPayload.swift
    DropDecoder.swift
    FileDescriptorSource.swift
    HandoffService.swift
    ExportService.swift
    ShareService.swift
    QRCodeService.swift
    HandoffStore.swift
    HandoffTrayView.swift
  Sources/CaptureFeature/
    CaptureModels.swift
    CapturePreferences.swift
    SourceContextProvider.swift
    QuickCaptureService.swift
    ScreenshotService.swift
    RegionSelectionController.swift
    CaptureStore.swift
    QuickCaptureView.swift
  Sources/ClipboardFeature/
    PasteboardClient.swift
    ClipboardPolicy.swift
    SensitiveAppsPolicy.swift
    ClipboardMonitor.swift
    ClipboardSearch.swift
    ClipboardStore.swift
    ClipboardShelfView.swift
  Tests/<module name>Tests/
LedgeIntegrationTests/
LedgeUITests/
LedgePerformanceTests/
Scripts/check-coverage.sh
Scripts/check-third-party-licenses.sh
Scripts/verify-public-apis.sh
Scripts/measure-idle-energy.sh
.github/workflows/ci.yml
docs/architecture/public-api-boundaries.md
docs/compliance/source-provenance.md
docs/testing/hardware-matrix.md
docs/testing/app-review-notes.md
```

Feature modules depend on `LedgeDomain`, never on each other. The app target is the only composition root. Platform adapters conform to small protocols; tests use actors or immutable fakes at framework boundaries.

## 6. Core Interfaces

```swift
public protocol ShelfRepository: Sendable {
    func insert(_ draft: ShelfItemDraft) async throws -> ShelfItem
    func importFile(_ request: FileImportRequest)
        -> AsyncThrowingStream<ImportProgress, Error>
    func item(id: UUID) async throws -> ShelfItem?
    func list(_ query: ShelfQuery) async throws -> [ShelfItem]
    func setFavorite(id: UUID, isFavorite: Bool) async throws -> ShelfItem
    func setTaskComplete(id: UUID, isComplete: Bool) async throws -> ShelfItem
    func export(id: UUID, to destination: URL) async throws -> ExportReceipt
    func delete(id: UUID) async throws
    func purgeExpired(before date: Date) async throws -> PurgeReport
}

@MainActor
public protocol ShellPanelControlling: AnyObject {
    func reveal(_ route: ShelfRoute, reason: RevealReason, screenID: String?)
    func dismiss(reason: DismissReason)
    func beginExternalInteraction(_ kind: ExternalInteractionKind) -> ExternalInteractionToken
    func endExternalInteraction(_ token: ExternalInteractionToken)
    func resetPosition()
}

public protocol MeetingProviding: Sendable {
    func authorization() async -> PermissionStatus
    func requestFullAccess() async throws -> Bool
    func snapshots() -> AsyncStream<MeetingSnapshot>
    func refresh() async
}

public protocol AudioControlling: Sendable {
    func snapshots() -> AsyncStream<AudioSnapshot>
    func setDefaultOutput(_ id: AudioDeviceID) async throws
    func setOutputVolume(_ scalar: Float) async throws
    func setOutputMuted(_ muted: Bool) async throws
    func setInputDeviceMuted(_ muted: Bool) async throws
}

public protocol NowPlayingProviding: Sendable {
    func snapshots() -> AsyncStream<NowPlayingSnapshot>
    func perform(_ command: TransportCommand) async throws
}

public protocol ClipboardHistoryProviding: Sendable {
    func snapshots() -> AsyncStream<ClipboardSnapshot>
    func search(_ query: String) async -> [ShelfItem]
    func copy(id: UUID) async throws
    func setPaused(_ paused: Bool) async
}

public protocol WallClock: Sendable {
    func now() -> Date
    func sleep(until deadline: Date) async throws
}
```

Production implementations use defaults only in the app composition root. Tests inject `TestClock`, `InMemoryShelfRepository`, `FakeEventStore`, `FakeAudioClient`, `FakePasteboard`, `FakeScreenProvider`, `FakeKeychain`, and `InMemoryFileSystem`; do not mock internal reducers or value models.

## 7. Performance, Reliability, and Accessibility Gates

| Measure | Release gate |
|---|---:|
| Warm hotkey callback to first shelf frame | p95 <= 100 ms |
| Hover dwell completion to first shelf frame | p95 <= 120 ms |
| Cold launch to status item and hotkey readiness | p95 <= 1.0 s |
| Idle CPU, clipboard disabled | <= 0.2% average over 10 minutes |
| Idle CPU, clipboard enabled | <= 0.5% average over 10 minutes |
| Idle wakeups with clipboard enabled | < 2/second average |
| Idle resident memory | <= 100 MiB |
| Resident memory with 500 clipboard entries | <= 150 MiB |
| Clipboard detection after copy, normal power | p95 <= 1.2 seconds |
| Clipboard detection after copy, Low Power Mode | p95 <= 2.2 seconds |
| Search across 500 entries | p95 <= 50 ms |
| Main-thread work | no app-owned operation > 16 ms |
| Hidden timers | zero animation/display-link timers; one optional clipboard timer and one nearest-deadline task |
| Network | zero outbound connections during every MVP flow |

Every transient surface must:

- Support Tab, Shift-Tab, arrows where semantically appropriate, Return/Space activation, Command-F search, Command-Return submit, Delete with confirmation where destructive, and Escape dismissal.
- Restore focus to the prior app after dismissal.
- Provide VoiceOver labels and values for countdowns, volume, mute state, item expiry, favorite state, progress, and errors.
- Use text plus icon/state rather than color alone.
- Disable spring/scale animation under Reduce Motion and avoid transparency-dependent readability under Reduce Transparency.
- Pass light/dark, Increase Contrast, and 200% text-size screenshots with no clipped critical action.

## 8. Product Validation Without Analytics

The release app collects and stores no interaction counters, analytics events, or usage history. Validate the product thesis outside the production data model through measured XCUITest journeys and explicitly consented, moderated beta sessions. A researcher starts and stops Instruments/signpost capture for the session, records aggregate task duration and success in a separate study worksheet, and never imports that worksheet into Ledge. Do not include app bundle IDs, titles, URLs, filenames, meeting details, clipboard classifications, or captured content. The app has no automatic export or upload path.

The thesis passes a beta gate when:

- Median time from reveal to completed action is under two seconds.
- At least 60% of shelf sessions complete one action and dismiss without navigation.
- Fewer than 5% of sessions require Settings or Reset Position to recover.
- Permission denial leaves hotkey, settings, and unrelated features usable in 100% of test cases.
- Idle energy and memory gates pass on the oldest supported Mac and a current Apple-silicon Mac.

## 9. Source Basis

- [NSScreen safe-area geometry](https://developer.apple.com/documentation/appkit/nsscreen)
- [Auxiliary top-left screen area](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc)
- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
- [Full-screen auxiliary window behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)
- [Display configuration changes](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification)
- [MediaPlayer Now Playing boundary](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
- [Core Audio device controls](https://developer.apple.com/documentation/coreaudio)
- [EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [NSPasteboard and access behavior](https://developer.apple.com/documentation/appkit/nspasteboard)
- [AppKit pasteboard privacy update](https://developer.apple.com/documentation/updates/appkit)
- [NSSharingService](https://developer.apple.com/documentation/appkit/nssharingservice)
- [App Sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Keychain Services](https://developer.apple.com/documentation/security/keychain-services)
- [AES-GCM in CryptoKit](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [Mac App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Sapphire AGPL-3.0 license](https://github.com/cshariq/Sapphire/blob/main/LICENSE)
- [Sapphire setup and readability report](https://github.com/cshariq/Sapphire/issues/16)
- [Sapphire CPU and memory report](https://github.com/cshariq/Sapphire/issues/18)
- [Sapphire helper-install failure report](https://github.com/cshariq/Sapphire/issues/14)

---
