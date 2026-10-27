# Ledge: notch shell and optional plugin apps

Status: approved for implementation by the user's subsequent implement/continue requests. This remains a target design, not a claim of complete implementation or release qualification. It supersedes the earlier design where an automation inbox coexisted with built-in feature routes. Installation, account connections and publication remain separate actions.

## 1. Product decision

User override (2026-10-27): register no global hotkeys, including optional ones. The user reported Command–Option–Space also opening macOS search. Hover is the primary entry; Finder/Spotlight reopen provides recovery. References to a global hotkey later in this historical design are superseded by this instruction.

**Ledge is a native notch interaction framework. Apps are plugins users choose to install; Ledge itself is not a collection of features.**

The user requested Notchy-like presentation, not Notchy's feature set. Borrow only the interaction grammar: compact presence, hover peek, deliberate expansion, fluid collapse, and a virtual island on notchless/external displays. Do not copy its branding, assets, implementation, feature inventory, pricing, or performance claims. Reference: [Notchy's official demonstration](https://notchy.dev/).

Every user-facing workflow—including GitHub opportunities, CI monitoring, notes, clipboard, meetings, and audio if offered—is an optional plugin app. The host owns infrastructure: geometry, navigation, rendering, input, package management, configuration, permissions, scheduling, connections, persistence, notification policy, diagnostics, and recovery.

There is **no menu-bar/status-item UI in the production product**, including a hidden preference that can revive the old feature dropdown. A Settings/Library window is appropriate for setup; it is not the everyday action surface. Recovery uses the global hotkey, Finder/Spotlight reopen, and CLI, not a toolbar icon.

## 2. Why the current version does not meet that decision

Checked against commit `40593c2`:

- `AppDelegate.applicationDidFinishLaunching` can still create `StatusItemController`; that class constructs the exact legacy Capture/Clipboard/Audio menu visible in the screenshot. The current source makes it preference-dependent, so the image alone does not prove which preference or executable was active. A read-only check of the current unsandboxed defaults domain found no `ledge.recovery.menuIcon` value; do not claim that switching that preference explains the image.
- `configureFeatureServices` constructs capture/audio/clipboard/calendar services independently of installed plugins. `installShelfView` switches over fixed feature routes. The home view always has a Capture action.
- `AppEnvironment` starts with all feature cases enabled. `ShelfRoute` is a closed feature enum. Hiding one icon would not make this architecture plugin-first.
- The local program runner, versioned manifests, encrypted store, scheduler, SDKs, and GitHub fixture are useful foundations. However, the current manifest describes a batch program, not a complete installable app with lifecycle, live views, configuration forms, and runtime capabilities.
- `AutomationHost` directly constructs a `GitHubProvider`; platform-neutral integration dispatch is not yet present.
- Shortcut editing/reset and UI tests need real wiring; diagnostics strings are not proof of notch behavior. The production agent still requires a properly Apple-signed installation. An ad-hoc-signed GUI starting successfully does not qualify automations.

## 3. Approaches considered

1. **Feature app with plugin extras.** Least migration work, but leaves first-party workflows privileged and the core growing with every feature. Reject: it contradicts the requested product.
2. **Arbitrary third-party native UI loaded into Ledge.** Flexible, but compromises GUI stability, signing boundaries, accessibility consistency, and attention policy. Reject for this release.
3. **A small native host, declarative plugin UI, supervised workers, and scoped system-service brokers.** Recommended proposal. All apps use one installation/instance/lifecycle contract. Batch jobs and event-driven apps use different execution adapters under that contract. Native first-party workflows use reviewed public-API brokers; they do not bypass installation or own windows.

The user subsequently approved implementation. Direct distribution and local Python/Node/shell programs are established requirements. Track actual completion and qualification separately in the implementation status report.

## 4. Experience and interaction contract

### Empty installation

First run introduces the hotkey and opens the app library. Zero apps are installed or enabled by default. No Calendar, Screen Recording, clipboard, network account, or background-agent permission is requested merely to view the library. Available offline starter packages are not active installations.

When closed with no activity, add no visible UI around a physical notch. On a notchless screen, do not leave a permanent pill unless the user pins one. Explicit invocation with zero apps shows only Install Apps, Settings, and recovery/health information; no Capture, Audio, Clipboard, or fake activity.

### Shell states

`hidden → compact(activity summary) → peek → expanded(app instance)`; dismissal returns to compact only while an allowed activity remains, otherwise hidden. Library and Settings are separate standard windows. Interactive sheets hold an interaction lease so the island does not vanish underneath permission, file, share, or confirmation UI.

- Derive the camera span and usable screen rectangles from public `NSScreen` safe/auxiliary areas. Render no content behind the camera. Use one presentation controller, not disconnected hover and inbox state machines. [Apple geometry](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc)
- Proposed defaults: hover dwell 200 ms, pointer-exit grace 350 ms, peek expiry 5 s, interruptible 180–240 ms expansion/collapse. Reduced Motion removes geometry animation. These are tuning inputs, not measured performance claims.
- Expanded default width 560 pt and maximum height 420 pt, always clamped to the selected usable display. Plugin content never selects global window frames, window levels, or animation code.
- Compact state shows at most two activity summaries plus an overflow count. Expanded navigation comes from installed, enabled instances; users may pin/reorder them. No fixed feature tabs.
- Hover/automatic peek never makes the panel key or activates Ledge. Explicit hotkey/click allows keyboard input; Escape/outside click returns focus to the previous app. Arrow keys, Tab, Return, and VoiceOver cover the same actions as pointer input.
- Default to the built-in notched display when available. A user can choose a particular display or “follow pointer on explicit invocation.” If that display disappears, choose a live fallback without losing a view/form. Use a virtual top-center island on notchless/external screens.
- Suppress automatic peek/hover in full-screen or presentation-safe mode. Explicit hotkey invocation remains possible. Use public display/Space/window metadata only, without introducing an Accessibility/Screen Recording requirement merely to operate the shell; if automatic-presentation safety is unknown, suppress it. Do not infer that current collection-behavior flags alone establish this guarantee; test the policy and real window behavior.
- Proposed shell target: event-driven idle, no animation/display-link loop when hidden; p95 hotkey-to-first-frame under 100 ms on the documented reference Mac. Measure idle CPU/wakeups, memory, and display-link use before claiming low battery use. Plugin workload is reported separately.

## 5. Architecture and the meaning of “everything is a plugin”

```text
Ledge GUI: notch controller + native renderer + Library/Settings + recovery
      ↕ authenticated, versioned host transport
Ledge host: registry + instances + grants + scheduler + state/outbox + actions
      ├─ command adapter: short Python / Node / shell / native invocations
      ├─ service adapter: supervised, opted-in event-driven workers
      └─ capability broker: scoped OS services + connection transport
                 ↕
       Optional plugin apps / optional connection-provider packages
```

The GUI and `AutomationHost` must not import AudioFeature, CaptureFeature, ClipboardFeature, MeetingFeature, HandoffFeature, or GitHubIntegration to select workflows. Reusable infrastructure has no feature menu or feature-specific route enum. Package/SDK contract modules are shared; concrete adapters are composed outside the kernel.

Public OS operations that require macOS permission/GUI involvement remain broker implementations: user-mediated screenshot/file/share requests, scoped pasteboard subscriptions, audio-device controls, and calendar reads. This is a technology boundary, not a license to put a Clipboard app or meeting-ranking logic back in the host. Each broker is lazy, lease-bound, stops when its last enabled subscriber disappears, and has no plugin-specific UI. Optional first-party app packages own the workflow, configuration, state transformations, and declarative presentation.

For v1, interactive/TCC-backed brokers live in the GUI. Closing the notch/window leaves that GUI process resident; quitting it makes these capabilities unavailable, visibly pauses dependent apps, and never silently reopens a permission UI. Headless scheduled apps can continue only after an explicit keep-running choice. The agent returns `capabilityUnavailable` for a missing GUI broker rather than pretending success. A later headless broker requires its own TCC/signing qualification.

Trusted workers execute out of process. No downloaded dynamic library, SwiftUI view, JavaScript web view, arbitrary HTML/CSS, or plugin-created `NSWindow` is loaded by the host. Applets using HTTP/WebSocket listening are not an implicit capability; no unauthenticated local API is introduced.

## 6. Unified package, instance, and UI contracts

User-facing terminology: **Apps** in the library, **plugins** in developer docs. A package is code plus manifest/assets. Installation pins its verified version. An instance is one named configuration, e.g. “Swift issues” and “Bazel issues” from the same app; a job is one scheduled invocation belonging to that instance.

Proposed new contracts, alongside a compatibility adapter for existing v1 local-command manifests:

- `PluginManifestV2`: schema version 2; reverse-domain ID; semantic version; host API range; publisher; runtime; entry; configuration/UI schema references; declared commands; requested scoped capabilities; optional provider dependencies. Reject unknown major versions. Explicitly label manifest examples as v2, never pass them into the v1 validator.
- `PluginInstallation`: installation ID, package ID/version/content digest, publisher verification status, source, install state and approved grants. A bundled package is not an installation. One active version per package in v1.
- `PluginInstance`: instance ID, installation ID, name, validated config, connection references, scheduling/event triggers, delivery preferences, display/pin preferences, revision and enabled state. Instances default disabled until setup completes.
- `PluginPresentation`: protocol version, instance ID, view ID, monotonic revision, sensitivity, compact summary, optional live activity and host-rendered view tree. Views support bounded text/markdown without raw HTML, rows, lists, sections, badges, progress, image handles, buttons, toggles, selections, and forms. Host-owned navigation and permission chrome cannot be replaced.
- `RunResultV2`: existing events/state/record mutations plus optional `viewSnapshot { presentation, checkedAt, staleAfter }`. A successful command commits its validated last-successful view snapshot in the same transaction, allowing an interactive app to remain visible after the process exits without keeping a worker alive. Mark outdated snapshots as stale; an expiring live-activity overlay is not the persistent app view. Failed commands do not overwrite the last successful snapshot. Disabled apps hide it; uninstall's data-retention choice also covers snapshots.
- `PluginActionRequest`: installation/instance/command IDs, validated arguments, view revision, grant/config revision and request ID. Resolve identity from the authenticated channel; payload cannot choose another app/instance. Reject stale/disabled/uninstalled actions. Destructive actions require confirmation; command handlers receive arguments, not string-concatenated shell.
- `HostServices`: generic scoped state/records/assets, subscriptions, presentations, events, connection operations and user-mediated actions. Tokens stay in Keychain; workers receive opaque connection references, not credentials through the API. Public data returned from a connection remains untrusted input.
- `ServiceCheckpoint`: checkpoint ID, monotonic sequence within the current lease, expected durable state revision and a `RunResultV2` batch. `CommitReceipt` contains checkpoint ID and committed state revision. These are service transactions, not a fake final program exit.

Reuse existing limits unless explicitly versioned: 256 KiB RPC frames, 2 MiB child output per invocation, 64 KiB state, 16 KiB individual records and 25 MiB/50,000 records per instance. Initial UI limit: 200 nodes, nesting 8, list page 100, at most 3 actions per card, text body 8 KiB. Streamed updates are coalesced to at most 5 accepted presentations/s/instance and 10/s globally while visible, 1/s while hidden; floods are throttled and reported. Clock/progress can render from timestamps locally without running a worker every second. Images use bounded host-managed assets, not arbitrary file paths or credential-bearing URLs.

Command results keep transactional commit after a valid successful final response and exit. Service instances instead call `HostServices.checkpoint(lease:batch:) -> CommitReceipt`: each batch independently validates the active lease/config/grants, state revision and quotas, and atomically commits state/events/records/view plus the checkpoint receipt and payload digest. Repeating the same checkpoint ID/digest returns its receipt without repeating writes; the same ID with a different digest is an error. Previously acknowledged checkpoints survive a later worker crash; uncommitted output does not. Restarted workers read authoritative state and resume; semantic event source keys retain cross-lease deduplication. Checkpoints are limited to one/s/instance, burst 5; batch/coalesce more frequent observations without dropping them silently, and expose backpressure.

One writer per instance: command instances serialize invocations; service instances route actions and schedule/event triggers to the existing worker instead of starting a competing command writer. Services use a separate session-open/ready, action-request/reply, heartbeat and checkpoint protocol in `ServiceWorker`; do not modify the command runner to accept durable success before exit. A service action may checkpoint before replying, and its reply references the receipt. An unresponsive action times out visibly without assuming it never had effects.

Live presentation updates are transient, lease-bound and disappear on failure/disable; they cannot durably publish success. Service heartbeats expire after 30 s; persistent failure uses bounded restart backoff, pauses after 3 failures in 10 minutes, and exposes a restart action. Command timeouts remain 5–900 s, default 120 s. Do not use high-frequency cron as a substitute for subscriptions.

## 7. Apps library, installation, configuration, removal

Library sections: Discover, Installed, Connections, Developer. Discover starts from an offline first-party catalog shipped with the app; a remote signed catalog can be added later, with no execution or automatic installs during browsing. Users can inspect purpose, screenshots/sample views, publisher, version, source, runtimes, permissions, network scope, and background behavior before installing.

Lifecycle: `available → verified → installedDisabled → configured → enabled → paused/failed → removed`. Installation, configuration, enablement, connection, and OS permission are separate transitions. Installing an app never automatically starts a schedule, imports shell hooks, or enables monitoring. Missing runtime/service/signing prerequisites are actionable setup states, not an endless spinner.

Use JSON configuration plus the existing bounded schema subset, with a versioned UI schema for labels, descriptions, secrets-as-connection-pickers, arrays/repository lists, enums, path pickers and schedule controls. A complete form and advanced JSON edit the same canonical instance document. Preview changes, validate atomically, preserve the last valid config, and explain capability changes before approval. Users control per-instance pins, position, schedule/timezone, connections, noise level, quiet hours and retention. Configuration export contains no credentials.

Local folders and `.ledgeplugin` bundles are supported. Installation stages to a temporary directory, rejects traversal/symlinks/special files/oversize payloads, verifies a deterministic digest and declared publisher signature when applicable, then atomically promotes the package. No `npm install`, `pip install`, package scripts or arbitrary setup hook runs during installation. Bundled official native worker executables must be nested-signed/notarized with the app; local scripts require explicit “runs as you” trust, not a fake sandbox badge.

Updates are explicit: stage/verify, show changes to grants/config/data, stop old instances, snapshot instance data, migrate on a copy using bounded trusted-worker execution, health-check, atomically switch all affected instances, or restore the prior version/config/data/grants. No silent grant expansion and no partial rollout across shared instances. New native official releases ship through the signed app update initially, not a generic executable downloader. Removing a dependency shows dependents and never silently removes unrelated apps.

Disable immediately revokes instance leases, subscriptions, scheduled work, queued actions and transient views. Uninstall does the same, removes its navigation, and asks whether to retain encrypted data. Retained archives are inactive and cannot execute. Reinstall restores only after confirmation; never resurrect a former schedule merely because the package ID matches. Connection deletion is explicit and warns about other dependent apps.

## 8. Connections are extensions too

Move GitHub implementation behind `IntegrationProvider`, registered by an optional reviewed provider package, rather than hard-coded `connect.github` branches in the kernel. The GitHub Opportunities and CI apps can share that provider and a user-approved connection without sharing unrestricted state or tokens.

The host's generic credential/HTTPS broker injects authentication for fixed, reviewed provider operations. Provider metadata declares allowed origins, parameterized paths, fixed GraphQL documents, schemas, and limits; it cannot receive raw tokens or request arbitrary authenticated URLs. Bind each connection to the approved provider identity/digest and scopes; another provider cannot name that connection to acquire its authentication, and changed operations/origins require reapproval before use. Unknown providers/operations fail closed. Installing a third-party provider is higher-risk consent because approved operations can expose account data; the permission screen says so. Arbitrary native workers remain trusted-user code and can independently perform side effects—host grants do not sandbox them.

Preserve and finish GitHub's serial account queue, conditional caching, bounded pagination, HTTP-level budgets, rate-limit/reset/retry-after behavior, and secret redaction. Partial assignment/comments/PR evidence means unknown, not eligible. App actions revalidate contribution status before presenting an opportunity as current. No write/comment/claim permission is needed for the first shipped apps.

## 9. Proposed first-party catalog and scope

Launch the framework with a small, optional developer catalog—not Notchy's feature list:

| App | Purpose | Execution |
| --- | --- | --- |
| GitHub Opportunities | The original repository/skills-aware contribution workflow, conservative evidence, quiet baseline, deduplicated alerts, revalidation | Scheduled command + optional GitHub provider |
| GitHub CI Watch | Selected repository/branch workflow completion and failure, with links and timestamps | Scheduled command + the same provider |
| Command Result | User-selected local program produces a status/card; manual or scheduled runs | Command adapter, explicit executable/argument picker |

Agent completion is an SDK example using an explicit authenticated CLI message/command initially; don't auto-edit agent or shell configuration. Old capture/clipboard/meeting/audio/handoff workflows may later be offered as optional apps. They are not mandatory launch blockers, and no old feature route remains as a hidden fallback. An old feature not yet packaged is listed as unavailable; retain its data and explain how to recover/export it.

## 10. Migration and release conditions

Migration is copy-first, journaled and idempotent. Preserve old shelf/database/Keychain data, v1 plugin package hashes, existing job/event identities and unread/delivery state. V1 jobs become instances using a compatibility adapter, initially paused for review; preserve deduplication keys so resume does not replay all history. Legacy enabled flags produce an offer to install matching optional apps, never an automatic install/permission grant. The menu-icon preference is retired and ignored. Run only one reviewed migration path; ambiguous old/new storage requires an actionable recovery window, not swallowed initialization errors.

Record build/commit/install path and process version in diagnostics. Verify the actual running `/Applications/Ledge.app`, not just a successful Xcode build. Install/enable/restart is a signed lifecycle test: keep production XPC signature checks, do not fall back to an unauthenticated service to make local demos appear working. Catalog and non-running view fixtures must work without a registered agent. Debug-only foreground-host mode can aid development, but is labeled non-production and never enabled by a Release environment variable. Service registration uses Apple's public, user-approved `SMAppService`. [Apple service management](https://developer.apple.com/documentation/servicemanagement/smappservice)

Acceptance requires: zero status items on fresh and upgraded installs; zero installed apps means zero feature workers/subscriptions; Library works without credentials/agent; install a starter without rebuilding the GUI; multiple independently configured instances; immediate disable/uninstall; no stale actions or post-stop commits; no duplicate events across restart/sleep; real keyboard/VoiceOver and notched/notchless/external/full-screen tests; measured idle behavior; signed GUI/agent/CLI/official workers on a clean Mac. The existing red UI-runner and coverage gates are not waived.

## 11. Delivery order

1. Correct the product shell first: no status item, usable empty notch, recovery, and animated states with fixture content.
2. Deliver the package/instance lifecycle and native renderer using one tiny demo app; prove install/configure/disable/uninstall without GUI recompilation.
3. Extract generic capabilities and integration dispatch, then ship the three selectable developer apps and SDK workflow.
4. Migrate existing data/jobs, qualify signed installation and real displays, and remove obsolete feature composition. Port additional optional native apps only after the framework gate passes.

Non-goals: arbitrary native UI injection, untrusted-code sandboxing, a public marketplace backend, billing, cloud runners, always-online cron, app-specific hard-coded tabs, or another menu bar.
