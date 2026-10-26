# Ledge Developer Automation Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run developer-supplied local programs on reliable schedules, give them scoped integrations and native cards, and deliver useful GitHub contribution alerts at the macOS notch.

**Architecture:** A signed user LaunchAgent owns scheduling, execution, integrations and durable state. The native app owns the notch, user configuration and presentation. Language-independent plugin programs use a versioned private JSON-RPC channel and return structured run results.

**Tech Stack:** Swift 6, macOS 15+, AppKit/SwiftUI, ServiceManagement, Foundation Process/XPC, SQLite, CryptoKit/Keychain, JSON Schema, Python and TypeScript SDKs. Direct signed/notarized distribution.

**Spec:** [Developer automation platform design](../specs/2026-10-26-developer-automation-platform-design.md).

## Global Constraints

- Explicit user decision: direct distribution; local scripts are essential.
- Preserve the native Swift 6/macOS 15 application; distribute a Developer ID signed and notarized app.
- The default install creates no persistent menu-bar status item.
- One bundled user LaunchAgent is registered with `SMAppService.agent(plistName:)`; no root daemon and no generated crontab/plist per plugin.
- `local.command` programs run with the logged-in user's access; broker grants are not an OS sandbox for arbitrary native code.
- No job executes on the GUI main actor; plugin processes never draw their own notch UI.
- V1 configuration format is JSON plus JSON Schema; GUI is generated from the same schema.
- Maximum two concurrent programs globally and one invocation per automation.
- Default run timeout 120 seconds, configurable 5–900 seconds.
- Preserve existing shelf data, encryption keys and payload formats; add a separate agent-owned `automation.sqlite`.
- No product code, installed app replacement, background registration, real schedules, external account changes, or commits are part of writing this plan.

## Review Focus

1. An incomplete GitHub baseline/enrichment must not silently miss opportunities or publish confident empty results (Task 9).
2. Killing the agent between an external side effect and local commit must not claim exactly-once execution or blindly rerun non-idempotent work (Tasks 3 and 6).
3. A changed plugin/config/account must not inherit unrelated grants, checkpoints or source identity (Tasks 1, 5 and 11).
4. Hidden/compact notch surfaces must not intercept the menu bar or retain a large invisible click region (Task 2).
5. Quitting, disabling background access or revoking credentials must actually stop the corresponding work instead of creating a restart/prompt loop (Tasks 4, 8 and 12).

## Delivery slices

| Slice | Tasks | Demonstration |
| --- | --- | --- |
| A: actual notch + contract | 0–2 | Fixture event arrives at real notch; hover, keyboard and reopening work |
| B: local automation | 3–7 | Local Python program runs from CLI/schedule and produces durable notch events |
| C: useful GitHub watcher | 8–9 | Quiet baseline, new qualifying issue, evidence, revalidation and no repeated alert |
| D: developer product | 10–11 | Generate, test, configure, debug and share a plugin without editing Swift |
| E: migration and release | 12 | Existing shelf data retained, helper lifecycle verified, signed distributable qualified |

Complete Slice B before introducing another provider. Complete Slice C before marketplace, remote execution, arbitrary web UI or workflow graphs.

## File and module map

All paths are relative to the repository root. Existing feature modules remain during migration.

```text
Packages/LedgeKit/Sources/
  AutomationDomain/      # Codable contracts, IDs, schedules, evidence and policies
  AutomationStorage/     # Agent-owned database, checkpoints, event outbox
  AutomationRuntime/     # Scheduling, claims, retries, run-result transactions
  PluginRuntime/         # Registry, executable resolver, processes, protocol framing
  IntegrationKit/        # Connection/grant broker and provider contracts
  GitHubIntegration/     # Typed GitHub requests, auth, caching, evidence normalization
  NotificationRouting/   # Deduplication, quiet hours, digests and delivery decisions
  AgentIPC/              # App/agent/CLI request and event interfaces
  ShellFeature/          # Evolve existing shell into real notch presentation
LedgeAgent/
  Main.swift
  AgentHost.swift
  AgentLifecycle.swift
  Resources/com.ledge.agent.plist
LedgeCLI/
  Main.swift
  Commands/
LedgeApp/
  App/AutomationAppCoordinator.swift
  App/AgentConnection.swift
  Settings/{Automations,Plugins,Integrations,DeveloperConsole}View.swift
Schemas/{plugin-v1,automation-v1,run-result-v1,card-v1}.schema.json
SDKs/python/ledge_sdk/
SDKs/typescript/src/
Examples/github-opportunities/
Examples/local-command/
```

The agent is the automation database's only writer. `AutomationRuntime` depends on domain protocols; storage, processes and providers are injected. `ShellFeature` consumes presentation models, not a running process or API token. Keep `IntegrationKit` independent of the GitHub plugin's ranking policy.

## Shared interface decisions

Define these contracts in Task 1; later tasks must use the same names. Pure data types are `Codable & Sendable`; stable IDs are string-backed wrappers, not a new enum case for every plugin.

```swift
struct AutomationDefinition { // complete Codable form follows the schemas
    let id: AutomationID
    let revision: Int
    let plugin: PluginReference
    let command: CommandID
    let trigger: ScheduleSpec
    let config: JSONValue
    let connectionBindings: [String: ConnectionID]
    let delivery: DeliveryPreferences
}
struct RunRequest { let id: RunID; let automation: AutomationDefinition; let scheduledAt: Date; let deadline: Date; let reason: RunReason; let mode: RunMode }
struct RunResult { let events: [HostEvent]; let statePatches: [StatePatch]; let recordMutations: [RecordMutation]; let summary: String? }
struct HostEvent { let sourceKey: String; let revision: Int; let card: CardDocument; let sensitivity: Sensitivity; let priority: EventPriority; let expiresAt: Date? }
struct GateResult { let status: GateStatus; let reason: String; let evidence: [EvidenceReference] } // pass | fail | unknown

protocol ScheduleEvaluating: Sendable {
    func next(_ schedule: ScheduleSpec, after: Date, limit: Int) throws -> [ScheduledOccurrence]
}
protocol ProgramExecuting: Sendable {
    func execute(_ request: RunRequest, channel: any HostCapabilityChannel) async throws -> RunResult
    func cancel(runID: RunID) async
}
protocol AutomationRepository: Sendable {
    func claim(_ occurrence: ScheduledOccurrence, now: Date) async throws -> RunLease?
    func complete(_ lease: RunLease, result: RunResult, now: Date) async throws
    func fail(_ lease: RunLease, outcome: RunOutcome, now: Date) async throws
    func recoverInterrupted(now: Date) async throws -> [RunRecord]
}
protocol IntegrationProvider: Sendable {
    var id: ProviderID { get }
    func call(_ request: IntegrationRequest, grant: VerifiedGrant) async throws -> IntegrationResponse
}
```

`CardDocument` is a versioned sum type: summary/list/detail/progress/health/form. `CardAction` contains an action ID and typed data; it never contains executable shell. `HostCapabilityChannel` offers typed integration reads, namespaced document/record reads, and logs. Event publication, record mutations and state writes are staged in the final `RunResult`. `RunMode` is live/preview/dryRun; dryRun is cooperative for arbitrary native program effects. The host attaches plugin/automation identity from the run lease rather than accepting identity in event payloads.

### Task 0: Establish a truthful test/build baseline

**Files:** modify `Ledge.xcodeproj/project.pbxproj`, `Ledge.xcodeproj/xcshareddata/xcschemes/Ledge.xcscheme`, `.github/workflows/ci.yml`, `Scripts/check-coverage.sh`, `docs/testing/hardware-matrix.md`; add `Scripts/verify-test-targets.sh`.

**Consumes:** existing app/package and test source folders. **Produces:** registered `LedgeIntegrationTests`, `LedgeUITests`, `LedgePerformanceTests` Xcode targets and a runnable shared test action; package tests remain an explicit CI job.

- [ ] Add a failing verification that `xcodebuild -showTestPlans/-list` plus project/scheme parsing includes actual testables and an empty test run cannot pass CI. Wire the existing folders to the correct test target, app dependency and package products; do not turn test source existence into evidence of execution.
- [ ] Run `rtk swift test --package-path Packages/LedgeKit` with a matching selected Xcode. Record existing failures separately. Repair compile-only defects required for a real baseline; do not expand product scope.
- [ ] Run `rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -destination 'platform=macOS' -enableCodeCoverage YES -resultBundlePath .build/LedgeBaseline.xcresult` and require a nonzero executed-test count.
- [ ] Replace maximum-of-any-coverage-value parsing with target/file line counts; low-coverage targets must not be hidden by one 100% file. Verify fixtures where one target has 100% and another 0% do not pass a per-target floor. Record coverage exclusions explicitly.
- [ ] Verify build, scan and diagnostics results using the selected toolchain, never a hard-coded Downloads/Xcode path. Review the baseline before Task 1.

### Task 1: Versioned domain, manifests and configuration

**Files:** create `AutomationDomain/{Identifiers,PluginManifest,AutomationDefinition,ScheduleSpec,RunRecord,HostEvent,CardDocument,CapabilityGrant,IntegrationRequest,JSONValue,EvidenceReference,PluginRecord}.swift`; create `Schemas/*.schema.json`; modify `Packages/LedgeKit/Package.swift`; test `Tests/AutomationDomainTests/{Manifest,CardSchema,ConfigurationDiff}Tests.swift`.

**Consumes:** design §§7–11. **Produces:** shared types above plus `ManifestValidator.validate(data: Data) throws -> PluginManifest`, `ConfigurationValidator.validate(data: Data) throws -> [AutomationDefinition]`, and `ConfigurationDiff.make(current:proposed:) -> ConfigurationDiff`.

- [ ] Write failing schema tests: unknown major protocol rejected; duplicate IDs rejected; unknown commands/grants rejected; tokens cannot occupy a connection-reference field; source identity cannot be supplied by events; ≥4 card actions rejected; 101 events rejected. Assert a manifest with unsupported `runtime.kind` is disabled, never interpreted as a command.
- [ ] Run `rtk swift test --package-path Packages/LedgeKit --filter AutomationDomainTests`; expect missing module/validator failures first.
- [ ] Implement closed versioned schemas and Codable contracts. Validate numeric bounds, JSON nesting depth, command IDs, path containment and namespaced IDs at boundaries. Reject duplicate JSON object keys before normalization. Keep editable configuration revisions immutable.
- [ ] Generate Swift/SDK fixtures from the same schema examples. Add golden round-trips and migration fixtures; require last-valid-config preservation on invalid import and explicit diff for deletion.
- [ ] Re-run the target tests; success means schemas and typed round-trips agree. No actual job executes in this task.

### Task 2: Actual notch geometry and activation

**Files:** modify `ShellFeature/{ScreenDescriptor,ShellPanel,ShellPanelCoordinator,ShelfRootView,HoverTriggerPanel}.swift`, `LedgeApp/App/{AppDelegate,LedgeApp}.swift`; create `ShellFeature/{NotchGeometryResolver,NotchShape,NotchPresentationStore,DisplayMonitor,HoverActivationController,NotchCardRenderer}.swift`; test `Tests/ShellFeatureTests/{NotchGeometry,NotchPresentation}Tests.swift`, `LedgeUITests/NotchActivationUITests.swift`.

**Consumes:** Task 1 cards and existing `ShellReducer` concepts. **Produces:** `NotchGeometryResolver.resolve(screen: ScreenDescriptor, state: NotchPresentationState) -> NotchPlacement`, `DisplayMonitor.snapshots() -> AsyncStream<[ScreenDescriptor]>`, and `NotchPresentationStore.present(_ card: CardDocument, reason: PresentationReason)`.

- [ ] Write failing geometry tests using asymmetric auxiliary regions, negative display coordinates, scaled/mirrored screens and absent notch data. Pin `expanded.frame.maxY == screen.frame.maxY - safeArea.top`; content never overlaps the camera/menu region; the hidden hit region fits only the derived notch span. Remove old assumptions that a floating fixed-width pill is notch integration.
- [ ] Add state tests for 250 ms dwell, 350 ms exit grace, Escape, reduced motion, full-screen suppression, disconnect fallback, external redaction and a new event arriving while an editor is focused. No Home reinstall during editing.
- [ ] Run `rtk swift test --package-path Packages/LedgeKit --filter Notch`; confirm the new tests fail against old geometry/wiring.
- [ ] Implement the measured state machine and resize the real NSPanel for hidden/peek/expanded. Connect production tracking areas and screen/Space change notifications. Use CoreGraphics display identity and built-in classification; no pointer polling or display link.
- [ ] Disable the default status-item UI and add app reopening/hotkey recovery plus normal Settings window. Retain an optional recovery-only status icon setting. Feed one fixture card through the same renderer as production.
- [ ] Run registered `NotchActivationUITests` and manually exercise notched display, external-only/clamshell, Space change and full-screen. Test actual frame bounds and activation, not only diagnostics strings.

### Task 3: Durable automation store and transactional outbox

**Files:** create `AutomationStorage/{SQLiteAutomationStore,AutomationMigration,RunLeaseStore,PluginStateStore,PluginRecordStore,EventOutboxStore,EncryptedAutomationPayloads}.swift`; test `Tests/AutomationStorageTests/{Transaction,Recovery,Retention}Tests.swift`; preserve existing `LedgeStorage` source/payloads.

**Consumes:** Task 1 contracts, audited existing crypto and SQLite primitives. **Produces:** `SQLiteAutomationStore: AutomationRepository`, plus `claimDeliveries(now:limit:)`, `acknowledgeDelivery(id:receipt:)` and read-only snapshot/query methods for IPC.

- [ ] Add failing tests for duplicate occurrence claims, stale lease completion, rollback after staged state/record update, restart recovery, missing Keychain key, and event retention without deleting dedup tombstones. Pin 64 KiB document, 16 KiB record and 25 MiB/50,000-record per-instance limits; namespace isolation and byte/page bounds must hold on queries.
- [ ] Pin the central transaction invariant:

  ```swift
  // Given a claimed run and an injected failure before commit:
  #expect(try await store.state(namespace: jobID) == oldState)
  #expect(try await store.pendingEvents(jobID: jobID).isEmpty)
  // A successful retry commits state, checkpoint and outbox together once.
  ```

- [ ] Run `rtk swift test --package-path Packages/LedgeKit --filter AutomationStorageTests`; then implement the separate versioned database and unique occurrence/event constraints.
- [ ] Store encrypted event/config/state/log payloads using a separately namespaced Keychain key; never recreate an unreadable existing key and call the database empty. App/agent/CLI access controls are part of Task 4 signing qualification.
- [ ] Add lease recovery semantics: mark orphaned runs interrupted; record whether replay is allowed. Use injected filesystem/clock/crypto failures to verify fail-closed commit and cleanup behavior.
- [ ] Re-run tests and inspect a fixture SQLite/vault directory for plaintext test secrets. Confirm existing shelf fixture files and key-service configuration remain untouched.

### Task 4: Signed agent, authenticated IPC and lifecycle

**Files:** create `LedgeAgent/{Main,AgentHost,AgentLifecycle}.swift`, `LedgeAgent/Resources/com.ledge.agent.plist`, `AgentIPC/{AgentProtocol,AgentClient,PeerRequirement}.swift`, `LedgeApp/App/AgentConnection.swift`, `LedgeCLI/Main.swift`; modify Xcode project, xcconfigs, entitlements and `LoginItemController.swift`; add registered `LedgeIntegrationTests/AgentLifecycleTests.swift`.

**Consumes:** Tasks 1 and 3. **Produces:** bundled `LedgeAgent` and `ledge` executables, one `com.ledge.agent` Mach service, `AgentClient.status()/apply()/run()/stop()/events(afterSequence:)`, and explicit background-item controls.

- [ ] Write failing IPC tests for invalid signing identifier, wrong role, oversized message, protocol version mismatch, reconnect sequence and a plugin attempting an admin operation. A plugin's private run pipe cannot register/change jobs.
- [ ] Add lifecycle integration assertions: `stopAll` prevents a supervised restart from executing jobs; approval-denied registration keeps manual UI recovery available; GUI reconnect drains existing events.
- [ ] Register a user LaunchAgent through `SMAppService.agent(plistName:)`, with its plist under `Contents/Library/LaunchAgents` and executable under `Contents/MacOS/LedgeAgent`. Authenticate both peers using Team ID + exact signing identifiers before resuming XPC; validate effective user/session and method roles.
- [ ] Add separate Developer/Release entitlement configurations for trusted native execution, Keychain access and required public APIs. Keep Hardened Runtime/library validation. Test Keychain sharing/references using the actual signed agent and GUI; do not qualify it from an ad-hoc build alone.
- [ ] Implement standard Quit/stop, explicit keep-runner option and registration approval state. Intentional stop must be persisted before process exit. No automatic consent prompt at every launch.
- [ ] Run signed `AgentLifecycleTests` on a disposable test profile, unregister afterward, and verify no jobs/processes remain. CI without signing uses a test transport and reports the signed hardware gate as unqualified.

### Task 5: Local executable runner and protocol

**Files:** create `PluginRuntime/{PluginRegistry,ExecutableResolver,ProgramRunner,JSONRPCChannel,OutputBudget,ProcessCancellation}.swift`, `SDKs/python/ledge_sdk/{__init__,protocol,context}.py`, `Examples/local-command/*`; test `Tests/PluginRuntimeTests/{Framing,ProgramRunner,Registry}Tests.swift` and `Fixtures/programs/*`.

**Consumes:** Task 1 `RunRequest/RunResult`, Task 4 run-scoped identity. **Produces:** `ProgramRunner: ProgramExecuting`, `PluginRegistry.resolve(_ reference: PluginReference) throws -> InstalledPlugin`, and Python `run(handler)` / `Context` APIs.

- [ ] Write failing process fixtures: malformed JSON; partial frame; 256 KiB+1 frame/final response; 2 MiB+1 aggregate protocol output; stdout diagnostics; stderr flood; no completion; exit failure after a valid completion; endless process; spawned child. Assert no failed invocation can publish staged events, record mutations or state.
- [ ] Add registry assertions: pinned source changed → disabled until reinstallation; `dev link` changes allowed only for that explicit live directory; path traversal/symlink escape rejected; no installation hook executes.
- [ ] Run `rtk swift test --package-path Packages/LedgeKit --filter PluginRuntimeTests`; implement argv-based launch without a shell interpolation layer, absolute interpreter resolution, minimal environment and explicit working directory.
- [ ] Implement private bidirectional JSON-RPC framing, version handshake, monotonic request IDs and budget/cancellation checks. Retain final result until process exit 0 and complete validation; cleanly close both streams.
- [ ] Implement timeout and process-group termination with the three-second grace from the spec. Document cooperating-process limitations; do not claim a hard RSS sandbox or prevention of deliberate daemonization.
- [ ] Run fixture tests and Python protocol conformance tests through `rtk`; verify no lingering fixture processes. The existing-program wrapper produces a valid run result without using an SDK.

### Task 6: Scheduler, run coordinator and failure recovery

**Files:** create `AutomationRuntime/{CronSchedule,IntervalSchedule,AutomationScheduler,RunCoordinator,RetryPolicy,OccurrenceIdentity}.swift`; test `Tests/AutomationRuntimeTests/{Cron,DST,Misfire,Overlap,Recovery}Tests.swift`.

**Consumes:** Tasks 1, 3 and 5; injected `ScheduleClock`, `AutomationRepository`, `ProgramExecuting`. **Produces:** `AutomationScheduler.start()/stop()/reconcile(now:)`, `RunCoordinator.enqueue(_ occurrence:)`, and the `ScheduleEvaluating` implementation.

- [ ] Write failing tests for numeric five-field grammar, conventional day-of-month/day-of-week OR, Sunday 0/7, invalid six-field/macro/timezone input, and next-five-occurrence preview.
- [ ] Pin DST/misfire/overlap behavior with a fake clock. For `30 2 * * *` in `America/New_York`, skip the spring gap; the repeated autumn local minute fires once. After 20 missed slots, `run-latest` enqueues at most one slot within 24 hours; `skip` enqueues zero. Three requested programs run at most two globally; a job never overlaps itself.
- [ ] Run `rtk swift test --package-path Packages/LedgeKit --filter AutomationRuntimeTests`; implement a nearest-deadline timer with leeway, durable occurrence claims, clock/wake reconciliation and persisted retry scheduling. Test generic 0–60-second deterministic jitter, preserve occurrence identity, and start the execution timeout from actual process launch.
- [ ] Route run success through `AutomationRepository.complete`; route timeout/cancellation/interruption through explicit outcomes. One transient retry after ≥60 seconds, three terminal failures pause auto-runs, one health event per incident. Never automatically retry uncertain non-idempotent effects.
- [ ] Add crash-after-execution/before-commit and backward-clock tests. Assert read-only/idempotent replay and non-idempotent manual-review outcomes differ. Repeated scheduler reconciliation cannot create a second occurrence.
- [ ] Run `AutomationRuntimeTests` and signed agent smoke checks; verify no one-second wake loop and no per-job launchd registration.

### Task 7: Event policy and notch delivery

**Files:** create `NotificationRouting/{EventRouter,DeliveryPolicy,DigestAccumulator,DeliveryCoordinator}.swift`, `LedgeApp/App/{AutomationAppCoordinator,NativeNotificationBridge}.swift`; evolve `ShellFeature/{ActionResolver,NotchCardRenderer,NotchPresentationStore}.swift`; test `Tests/NotificationRoutingTests/*` and `LedgeUITests/AutomationEventUITests.swift`.

**Consumes:** Tasks 1–4 event snapshots/outbox and Task 2 notch renderer. **Produces:** `DeliveryPolicy.evaluate(event:context:) -> DeliveryDecision`, `DeliveryCoordinator.drain(now:)`, and dynamic `CommandDispatcher.perform(actionID:eventID:)`.

- [ ] Write failing tests: quiet hours spanning midnight; external-display sensitivity; plugin urgency unable to override mute; one peek/60 seconds and three/10 minutes; a repeat event updates one inbox item; delivery reconnect does not blindly replay old outbox entries.
- [ ] Verify `mute` still stores events and `disable automation` stops execution; the two actions must not alias. Test GUI-disconnected events remain durable without trying to render or repeatedly relaunch the app.
- [ ] Run `rtk swift test --package-path Packages/LedgeKit --filter NotificationRoutingTests`; implement native summary/list/detail/progress/health/form cards and typed action validation.
- [ ] Wire agent changes to an observable app store and current route. Passive peeks stay non-key. Host actions open only validated provider resources/HTTPS URLs or declared commands after a user gesture; no payload-provided shell code.
- [ ] Add optional authorized macOS notifications via the GUI bridge; default to notch/inbox, avoid double delivery, and preserve macOS permission/Focus behavior.
- [ ] Run actual event UI tests and crash-window injection. Report at-least-once physical presentation risk honestly while ensuring unique durable events/receipts.

### Task 8: GitHub connection and typed read provider

**Files:** create `IntegrationKit/{IntegrationBroker,CredentialStore,GrantEvaluator,ProviderRegistry}.swift`, `GitHubIntegration/{GitHubProvider,GitHubHTTPClient,GitHubModels,GitHubRatePolicy,GitHubEvidenceClient,GitHubConnection}.swift`; test `Tests/GitHubIntegrationTests/{HTTP,RateLimit,Permissions,Evidence}Tests.swift` with recorded HTTP fixtures.

**Consumes:** Task 1 integration contracts and Task 4 agent authority. **Produces:** three typed read operations from design §9, per-account serial queue and secure connection references.

- [ ] Write failing tests: token never returned to plugin/logs; repo outside grant rejected; revocation blocks the next broker call; redirects cannot forward credentials to another origin; stale account cache never appears under a new account.
- [ ] Add fixtures for 200/304/pagination, 401, 403/429 with retry-after/reset, 404 ambiguity, GraphQL partial errors, unsupported `assignedActors` and truncated evidence connections. Unsupported/incomplete assignment/PR evidence must become `unknown`.
- [ ] Run `rtk swift test --package-path Packages/LedgeKit --filter GitHubIntegrationTests`; implement local Keychain token connection, identity validation and read-only typed operations. No remote auth service or hard-coded OAuth secret.
- [ ] Implement stable conditional request keys including account/provider/resource/query version, serial request queue, rate backoff and bounded response/cache storage. Hold grants/resources on every request, including continuations and redirects.
- [ ] Add Settings/CLI Connect with secure field/stdin, minimal permissions and explicit account/resource display. Anonymous mode is preview only. Reconnecting is a deliberate action, not a repeated permission prompt.
- [ ] Re-run mocked contract tests; separately mark any opt-in live public read smoke test as live evidence. Never use user's private repos or broad existing `gh` tokens by inference.

### Task 9: GitHub Opportunities plugin, eligibility and deltas

**Files:** create `Examples/github-opportunities/{ledge-plugin.json,config.schema.json,watch.py,eligibility.py,ranking.py,checkpoints.py,README.md}`, `Examples/github-opportunities/fixtures/*`, `Examples/github-opportunities/tests/*`; add host integration fixtures under `LedgeIntegrationTests/GitHubWatcherFlowTests.swift`.

**Consumes:** Tasks 5–8 SDK/provider/state/event services. **Produces:** installable sample with `scan` and `revalidate-issue`, the strict-contribution preset and explainable native opportunity cards.

- [ ] Write recorded-fixture tests for a baseline, new issue, newly unassigned older issue, trusted triage label, no affirmative triage evidence, assigned agent, draft PR closure, incidental PR reference, informal claim, blocked label and archived repo. Rank only all-pass candidates.
- [ ] Pin score components/threshold 70 and links explaining every nonzero component. Topic similarity is a possible-overlap hold, not proof. Reject issue text that attempts to inject commands into events or the runner.
- [ ] Run `rtk proxy python3 -m unittest discover -s Examples/github-opportunities/tests`; expect failures before implementing the sample helpers. Use no external packages unless a clear need is reviewed.
- [ ] Implement per-repository resumable baseline and daily reconciliation, scan-start watermark, five-minute discovery overlap, durable pending enrichment, per-account request budget 120/scan and 20 enrichments, starter maximum 10 repos. Use the ordinary plugin document/record API, maximum 50 records per byte-bounded result segment and durable continuations. Jobs run every 15 minutes with ≤60-second jitter. OR-label discovery must not accidentally use an AND REST label filter.
- [ ] Add failure assertions: crash after page 2, truncated PR evidence, enrichment timeout, one failed repository, permission loss, and baseline races. Affected partitions cannot advance/alert confidently; successful partitions may commit independently with visible coverage. No baseline completion while an undiscovered page remains.
- [ ] Implement no-repeat event keys and quiet baseline by default; adding a repo/account/config revision baselines only affected partitions. Old history retention cannot resurrect alerts. Optional eligibility re-entry alerts require an actual transition and seven-day cooldown; default remains once per issue.
- [ ] Test Open/Save/Snooze/Ignore/mute-repo. Before normal Open, revalidate and clearly report changed/stale eligibility; offer historical navigation deliberately. There are no GitHub write actions in this plugin.
- [ ] Run the full mocked pipeline through the actual agent/protocol and registered UI test. Demonstrate one new contribution candidate at the notch, with evidence and no repeat after app/agent restart.

### Task 10: Developer CLI, SDKs and local preview

**Files:** create `LedgeCLI/Commands/{Init,Validate,Dev,Test,Plugin,Automation,Run,Runs,Logs,Connect,UI}.swift`, `SDKs/typescript/{package.json,src/*}`, Python packaging/tests, `Examples/templates/*`, `docs/developer/{quickstart,plugin-protocol,testing}.md`.

**Consumes:** Tasks 1, 4–9 interfaces. **Produces:** documented commands in design §7, stable JSON output/exit codes and matching Python/TypeScript SDK APIs.

- [ ] Write CLI fixture tests for no agent, invalid manifest, denied connection, timeout, invalid template and invalid config replacement. Assert exact exit codes 0/2/3/4/5/6 and no token in argv/output.
- [ ] Implement template generation, offline schema validation, existing-program wrapper, fixture-backed `dev`, isolated test state, real native card preview and per-run structured logs.
- [ ] Implement `--dry-run` through a noncommitting run context: integration reads only, no persistent plugin state/records/events, no notifications or mutating host operation. Pass the mode to the program and document that independent native effects remain possible; fixture preview is the safer default for untested code. Explicit manual runs and scheduled invocations otherwise share one execution path.
- [ ] Add JSON-RPC golden vectors and run against Python, TypeScript and raw protocol fixtures. A developer command must work using its configured interpreter even when the login-shell PATH differs.
- [ ] Exercise the quickstart end to end on a clean test directory, measuring actual steps/time. Target first fixture card within 10 minutes and no Swift edit. Do not auto-install runtimes or run package installation hooks.
- [ ] Verify CLI optional shell shim removal leaves the signed app/agent functional; shipped binary paths and release allowlists agree.

### Task 11: Schema-driven configuration and recovery windows

**Files:** create `LedgeApp/Settings/{AutomationsView,AutomationEditorView,PluginsView,IntegrationsView,DeveloperConsoleView}.swift`, `ShellFeature/SchemaFormView.swift`; modify `SettingsView.swift`, `GeneralSettingsView.swift`, `DiagnosticsView.swift`; test `LedgeUITests/AutomationSettingsUITests.swift`.

**Consumes:** Task 1 schemas/diffs, Task 4 APIs, Tasks 6–10 status and diagnostics. **Produces:** complete install → configure → grant → preview → enable workflow without CLI and exportable config without secrets.

- [ ] Add failing UI cases for missing interpreter, malformed cron, revoked account, disabled runner, bad plugin update and agent reconnect. Show last success/next five runs/coverage independently; “agent running” is not “job healthy.”
- [ ] Generate supported form controls from the JSON Schema subset; unsupported controls remain editable in validated JSON, not silently dropped. Saving creates one immutable revision and a diff of changed grants/schedules.
- [ ] Build Plugins, Automations, Integrations and Runs/Logs windows. Include Run now, dry run, pause, stop current run, uninstall without data loss, optional purge, event delivery controls and per-repository policies.
- [ ] Permission expansion/account change requires visible grant review; content-only config change cannot overwrite unrelated grants or reset every baseline. Exports omit tokens and redact private values.
- [ ] Test keyboard/VoiceOver traversal, Reduce Motion, text sizing, first-launch and Finder/Spotlight reopen when no menu icon exists. A broken plugin cannot prevent Settings or Stop all from opening.
- [ ] Run registered settings/recovery tests and the full quickstart using the UI. Record any still-CLI-only control explicitly before calling this slice complete.

### Task 12: Bundled-feature migration and release qualification

**Files:** add `LedgeApp/App/BundledPluginRegistry.swift` and adapters under `Sources/BundledFeatureAdapters/`; update existing feature composition, `Ledge.entitlements`, Xcode embedding/signing, `Scripts/{verify-public-apis,check-third-party-licenses,measure-idle-energy}.sh`, `.github/workflows/ci.yml`, README and architecture/testing/compliance docs.

**Consumes:** Tasks 0–11 and existing shelf payloads/permissions. **Produces:** signed/notarized release candidate with tested lifecycle, real notch activation, one complete GitHub watcher and first-party features behind the same plugin registry.

- [ ] Convert Capture, Clipboard, Meetings, Handoff and Audio incrementally to bundled adapter IDs. Preserve all existing records and prompts; disable any incomplete adapter visibly instead of advertising it as migrated. Raw sensitive content does not become a general plugin capability.
- [ ] Add migration fixtures from the existing shelf database and interrupted automation schemas. Detect old sandbox-container versus direct-distribution Application Support/preferences paths; retain source data and write a migration receipt after verified copy, refusing ambiguous-store overwrite. Verify rollback/relaunch, locked Keychain, disk full, process failure and account disconnect leave recoverable state.
- [ ] Replace blanket helper/network rejection with exact signed executable/public framework allowlists; reject unexpected dylibs/helpers, remote install hooks and secrets. Record third-party licenses for schema/CLI/SDK tooling actually chosen.
- [ ] Run package tests plus registered app/integration/UI suites with nonzero counts and meaningful coverage. Use the existing hardware matrix for notched/notchless/clamshell/negative displays, Spaces/full-screen, sleep/wake, permission denial and quiet hours.
- [ ] Measure p95 reveal ≤100 ms, core agent <1 idle wakeup/sec, agent RSS ≤60 MiB and UI ≤120 MiB excluding separate program workloads. Verify low-power behavior and no repeating animations/timers when hidden.
- [ ] Build, Developer ID sign, verify nested binaries/entitlements/Keychain access, notarize and staple the release candidate through the authorized release workflow. Ad-hoc local builds do not qualify agent trust or distribution.
- [ ] In a disposable signed install, demonstrate standard Quit/Stop all halts scheduling and cooperative supervised work, keep-runner mode catches up once after sleep, and uninstall unregisters the agent before removing the bundle. Retain the documented limitation for deliberately detached native descendants. Require an explicit release/publish request before external distribution.

## Completion evidence

Keep a short execution ledger alongside this plan containing each task's changed paths, exact commands, pass/fail evidence and remaining hardware/signing gates. “Implemented,” “unit-tested,” “signed-integration-tested,” and “release-qualified” are separate states. No current doc or prior installation is evidence that these planned capabilities already exist.

The first handoff worth evaluating is Slice C: a real scheduled local program, scoped GitHub reads, a quiet baseline, one new evidence-backed opportunity on the physical notch, reliable dismissal, and no repeat after restart. Add the broader plugin ecosystem only after that works reliably.
