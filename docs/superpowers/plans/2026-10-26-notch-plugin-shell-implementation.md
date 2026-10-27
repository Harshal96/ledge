# Notch-First Plugin Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the feature/menu-bar app with a native notch framework whose user-facing apps are optional installable plugins.

**Architecture:** Keep the existing runner, encrypted persistence and scheduler, but separate host infrastructure from app workflows. Add one package/instance/lifecycle contract, a host-owned declarative native renderer, supervised command/service adapters, and lazy capability brokers. First-party apps use the same install/configure/enable/remove path as local apps.

**Tech Stack:** macOS 15+, Swift 6, AppKit/SwiftUI/Observation, public screen geometry, ServiceManagement/XPC, SQLite/CryptoKit/Keychain, Python/TypeScript SDKs; no new third-party runtime dependency is required.

**Spec:** `docs/superpowers/specs/2026-10-26-notch-plugin-shell-design.md`

## Global Constraints

- This is a proposed plan. No product code, dependency, installation, account, schedule or permission changes until the user approves implementation.
- There is no menu-bar/status-item UI in the production product.
- Every user-facing workflow is an optional plugin app. Available/bundled, installed, configured and enabled are distinct states.
- No downloaded dynamic library, SwiftUI view, JavaScript web view, arbitrary HTML/CSS, or plugin-created `NSWindow` is loaded by the host.
- Trusted workers run with the user's permissions; host grants are not an OS sandbox. Keep production XPC signature checks.
- New v2 contracts coexist with explicit v1 compatibility. Preserve existing encrypted data, credentials, event identities, delivery state and package hashes; migration is copy-first and journaled.
- UI limits: 200 nodes, nesting 8, list page 100, 3 actions/card, 8 KiB body. Existing RPC/state/record quotas remain as specified in the design.
- Shell defaults: 200 ms dwell, 350 ms exit grace, 5 s peek, 180–240 ms interruptible animation, width 560 pt, height at most 420 pt, clamped to the live display.
- Initial catalog: GitHub Opportunities, GitHub CI Watch, Command Result. No app is installed or enabled on a clean install.
- Prefix shell commands with `rtk`. Preserve dirty/concurrent work; no resets, automatic registration or credential setup.

## Review Focus

1. Upgrade with a legacy menu preference or stale executable: never revive a status item; diagnose the actual running build. Tests in Tasks 0, 1 and 10.
2. Remove/disable/update while a worker, action or subscription is pending: revoke leases, reject stale output, preserve unrelated instances. Tests in Tasks 3–5.
3. Permission denied, signing unavailable, GUI broker quit or provider disconnected: show actionable state without blocking Library/recovery or pretending work ran. Tests in Tasks 5, 7 and 10.
4. Malformed/flooded UI, provider data and action arguments: validate bounds/identity, stay responsive and never execute shell from data. Tests in Tasks 2, 5, 6 and 8.
5. Sleep/restart/display detach during live work: preserve deduplication and form state, avoid backlog storms/focus theft, clamp to an existing screen. Tests in Tasks 1, 2, 8 and 10.

## Ownership and file map

Keep current package boundaries where useful; split the large GUI composition file by responsibility. Names below are proposed new files/targets, not existing functionality.

- `AutomationDomain/PluginAppContracts.swift`: v2 manifest, installation, instance, grant and action identities. `AutomationDomain/PluginViewContracts.swift`: bounded view/activity payloads. Existing `Contracts.swift` retains v1 wire types.
- `PluginRuntime/PluginLifecycle.swift`, `PluginRegistry.swift`, `ServiceWorker.swift`: verified packages, lifecycle/revocation, event-driven supervision; existing `ProgramRunner.swift` stays the command adapter.
- `AutomationStorage/PluginInstanceStore.swift`, `PluginMigrationJournal.swift`: versioned installation/instance storage and migration. Existing SQLite store remains the transactional state/event implementation, generalized to instance identity.
- `AutomationHost/PluginHost.swift`, `PluginActionRouter.swift`, `HostServices.swift`: feature-agnostic orchestration. Existing `AutomationHost.swift` gets a v1 adapter and no direct GitHub composition.
- New targets `PluginUI` (SwiftUI renderer/forms) and `PluginSystemServices` (lazy native brokers); `IntegrationKit` owns generic provider/connection contracts. `GitHubIntegration` becomes an optional reviewed provider implementation.
- `ShellFeature/NotchPresentationController.swift`, `NotchTransition.swift`, `ShellPreferences.swift`, `RecoveryCoordinator.swift`: single shell state/policy; no feature routes.
- `LedgeApp/Library/{AppLibraryStore,AppLibraryView,PluginSetupView}.swift`, `LedgeApp/App/{PluginComposition,HostConnectionStore}.swift`: catalog/setup/composition. `AppDelegate.swift` wires infrastructure only; retire feature-specific code in `AppEnvironment.swift` after migration.
- `FirstPartyApps/catalog.json` and three package directories; `Examples/hello-app/`; versioned `Schemas/*-v2.schema.json`; SDK changes mirror those versions.
- Corresponding package tests plus `LedgeUITests/NotchShellUITests.swift`, `AppLibraryUITests.swift`, `PluginLifecycleUITests.swift`; release scripts validate actual signed bundle inventory, not an unqualified broad executable allowance.

## Task 0: Lock the baseline and expose build/runtime identity

**Files:** modify `LedgeApp/Settings/DiagnosticsView.swift`, `LedgeApp/Resources/Info.plist`, `.github/workflows/ci.yml`; test `LedgeIntegrationTests/PersistenceRecoveryTests.swift`; create `docs/testing/notch-plugin-acceptance.md`.

**Interfaces:** produce `BuildIdentity { version, build, commit, executableURL }` and a diagnostics snapshot distinguishing GUI, agent, signature/registration status and instance count. Do not expose secrets or probe permissions by requesting them.

- [ ] Write failing tests `diagnosticsReportsRunningBundleNotCheckout` and `unsignedHostIsUnavailableNotConnected`; assert path/commit match the launched fixture and unavailable agent does not block diagnostics. Capture current test/coverage failures without waiving them.
- [ ] Run `rtk swift test --package-path Packages/LedgeKit` and the focused integration tests; record failing new assertions separately from the existing UI-runner/authentication baseline.
- [ ] Add build identity and prerequisite states; create a copy-first migration fixture from v1 jobs/state/events and a clean-install fixture, with no real credentials.
- [ ] Verify build identity in the actual app bundle, gate fixtures with `rtk proxy python3 Scripts/tests/test-gates.py`, and `rtk proxy zsh Scripts/verify-test-targets.sh --project`. Preserve partial/failing coverage status.
- [ ] Commit only this task's files after review: `Expose truthful build and runner diagnostics`.

## Task 1: Remove the status-item product and make recovery real

**Files:** modify `LedgeApp/App/AppDelegate.swift`, Settings views, `ShellFeature/CarbonHotKeyRegistrar.swift`, `ShellState.swift`; create `ShellPreferences.swift`, `RecoveryCoordinator.swift`; remove production `StatusItemController.swift` usage; replace menu-dependent UI tests.

**Interfaces:** `RecoveryCoordinator.open(_ destination: HostDestination)`, `resetPosition()`, `register(_ binding: HotKeyBinding) -> RegistrationResult`; `HostDestination` contains library/settings and plugin instance IDs, not Capture/Audio/etc.

- [ ] Write `freshAndLegacyPreferencesCreateZeroStatusItems`, `finderReopenWorksWithZeroApps`, `conflictOrUnsupportedShortcutOpensRecovery`, and `resetPositionUpdatesTheRealPanel`. Seed the retired icon preference true and assert zero status-item creation; assert a real reset callback rather than a diagnostic string.
- [ ] Run the focused package/UI tests and demonstrate failure against the existing launch/menu/reset behavior.
- [ ] Delete status-item creation and the feature dropdown path, ignore/retire the old preference, remove menu-dependent help, wire configurable hotkey/reset, and make Finder/Spotlight reopen independent of feature services/agent. Preserve legacy feature data; don't start it.
- [ ] Verify hotkey, failed hotkey, Finder reopen and Settings on a running fixture with no installed apps. Run actual UI assertions under `rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -destination 'platform=macOS' -only-testing:LedgeUITests/NotchShellUITests ONLY_ACTIVE_ARCH=YES`; authentication failure is a blocker, not a pass.
- [ ] Commit after review: `Replace menu-bar entry points with notch recovery`.

## Task 2: One notch state machine and fluid native presentation

**Files:** modify shell panel/coordinator/geometry/state/reducer; create `NotchPresentationController.swift`, `NotchTransition.swift`; test `ShellFeatureTests/NotchPresentationTests.swift`, `NotchGeometryTests.swift`, `LedgeUITests/NotchShellUITests.swift`.

**Interfaces:** `NotchPresentationController.send(_ event: NotchEvent)` consumes injected clock/display/privacy/focus state; produces `NotchSnapshot { presentation, placement, contentID, interactionLease }`. Feature-independent states are hidden/compact/peek/expanded(instanceID).

- [ ] Write fake-clock tests pinning 200/350/5000 ms boundaries, no focus acquisition on hover, explicit keyboard acquisition/return, Reduce Motion, interaction-lease dismissal, full-screen suppression, asymmetric housing, negative display origin and display removal with form state preserved.
- [ ] Run `rtk swift test --package-path Packages/LedgeKit --filter Notch` and show the new timing/transition assertions fail against direct frame toggles.
- [ ] Implement one reducer/controller and interruptible animation; retain public geometry, camera-safe layout and event-driven idle. Add a virtual island to notchless screens without leaving one visible when empty unless pinned.
- [ ] Verify native panel frames/focus on actual displays and UI tests, not only state snapshots. Measure 100 hotkey transitions and record p95 against the proposed <100 ms target; inspect idle display-link/wakeup behavior.
- [ ] Commit after review: `Add unified notch presentation and focus policy`.

## Task 3: Versioned app packages, instances, grants and dynamic routes

**Files:** create `AutomationDomain/PluginAppContracts.swift`, `PluginViewContracts.swift`, `Schemas/plugin-app-v2.schema.json`, `plugin-view-v2.schema.json`; modify validators/Package.swift/SDK version negotiation; tests in `AutomationDomainTests/PluginAppContractTests.swift`.

**Interfaces:** produce `PluginManifestV2`, `PluginInstallation`, `PluginInstance`, `PluginPresentation`, `RunResultV2`, `ServiceCheckpoint`, `CommitReceipt`, `PluginActionRequest`, `CapabilityGrant`, `PluginLease`; identifiers/revisions follow design §6. Define `PluginViewNode` and `PluginCommandDefinition.argumentSchema`; no opaque type names are left for later tasks to invent.

- [ ] Write `v1ManifestAdaptsWithoutIdentityChanges`, `twoInstancesNeverShareImplicitState`, `unknownMajorAndUndeclaredCommandsFail`, `staleViewOrGrantRevisionRejectsAction`, and malformed numeric/duplicate-key/UI-depth/asset-reference fixtures. Assert exact quotas from the design.
- [ ] Run `rtk swift test --package-path Packages/LedgeKit --filter PluginAppContract` and verify the contracts are genuinely missing/failing.
- [ ] Add the bounded v2 schemas/contracts and explicit v1 adapter. Replace closed feature routes with instance destinations; expose compatibility errors instead of silently reinterpreting v1 JSON.
- [ ] Run full domain tests and cross-language JSON fixtures against Python/TypeScript SDK decoders; verify schema/API version compatibility in both directions.
- [ ] Commit after review: `Define plugin app instances and presentation contracts`.

## Task 4: Transactional installation, instance storage and revocation

**Files:** modify `PluginRuntime/PluginRegistry.swift`, `AutomationStorage/SQLiteAutomationStore.swift`; create `PluginLifecycle.swift`, `PluginInstanceStore.swift`, storage migration scripts/fixtures and lifecycle/storage tests.

**Interfaces:** `PluginLifecycle.install(source: PackageSource, consent: InstallConsent) async throws -> PluginInstallation`; `setEnabled(instanceID:enabled:)`, `remove(installationID:keepData:)`, `update(installationID:source:consent:)`; issue/revoke `PluginLease` keyed by installation/instance/config/grant generation.

- [ ] Write tests for available≠installed≠enabled, missing runtime, staged-copy failure, path traversal/symlink/special file rejection, changed digest, publisher mismatch, dependency conflict, disable during launch/commit, explicit retained-data reinstall and failed update rollback across two instances. Assert successful command exit retains an atomically committed view snapshot, failed results cannot replace it, and uninstall's retention policy covers it. Service checkpoints must be atomic, replay the same receipt after a lost acknowledgment, reject changed replay payload/stale state revisions, and survive crash after commit. No install hooks may run in these fixtures.
- [ ] Run focused registry/storage tests; assert the current copy-plus-registry implementation lacks these atomic lifecycle guarantees.
- [ ] Add encrypted versioned installation/instance/snapshot/checkpoint-receipt tables, staged promotion, explicit grants and transactional revocation. Commit `RunResultV2.viewSnapshot` with its result/state/events; annotate stale timestamps without rerunning a process for rendering. Provide `commitCheckpoint(lease:batch:) throws -> CommitReceipt` with receipt/payload digest and expected-state-revision checks in the same transaction. Update on copy, snapshot all affected instances and switch only after success. Default removed data to retained encrypted archive pending explicit delete; never reactivate automatically.
- [ ] Verify leases at scheduling, host calls, action routing and commit; preserve unrelated work. Run full SQLite restart/atomicity tests and fault-injection at each promotion step.
- [ ] Commit after review: `Add transactional plugin lifecycle and instance storage`.

## Task 5: Feature-agnostic host, command/service adapters and brokers

**Files:** modify `AutomationHost.swift`, `ProgramRunner.swift`, `AgentIPC/AgentClient.swift`; create `PluginHost.swift`, `HostServices.swift`, `PluginActionRouter.swift`, `PluginRuntime/ServiceWorker.swift`, `PluginSystemServices/*`, `IntegrationKit/IntegrationProvider.swift` and generic connection operation contracts; move concrete GitHub composition outside the host.

**Interfaces:** `PluginHost.invoke(instanceID:command:arguments:expectedRevision:) async throws -> InvocationID`; `HostServices.call(lease:operation:params:) async throws -> JSONValue`, `checkpoint(lease:batch:) async throws -> CommitReceipt`; `IntegrationProvider.perform(operation:connection:parameters:lease:)`; `ServiceWorker.start(instance:lease:)`, `dispatchAction(_:)`, `stop(lease:)`. Native GUI brokers implement the same scoped service transport, not custom app routes.

- [ ] Write tests for command arguments preserved end-to-end, revoked/stale/foreign leases, stop-before-spawn/after-exit, final-result atomicity, worker flood, 30 s heartbeat expiry, 3 failures/10 min pause, GUI broker disconnect, provider disconnect, and a core target dependency assertion banning concrete feature/GitHub imports. Assert service actions/triggers use one existing worker, checkpoints do not require exit, revoked checkpoints fail, and rate limits of one durable checkpoint/s/instance (burst 5) signal backpressure.
- [ ] Run focused host/runtime tests and show the direct GitHub composition and command-only adapter fail the new assertions.
- [ ] Extract generic orchestration; add a distinct service session-open/ready, serialized action/reply, heartbeat/checkpoint protocol, transient presentation leases and bounded restart backoff. One writer per instance: service actions route to that worker, command instances serialize invocations. Keep existing command limits, minimal environment, spawn cancellation gate and transactional final events. Add lazy OS broker subscriptions and opaque connection operations; do not weaken production signing or return tokens to workers.
- [ ] Run integration tests proving disabling the last app cancels its broker subscriptions, no GUI broker silently relaunches/presents permission prompts, and provider HTTP origins/templates/redirect rules fail closed. Assert connection references cannot cross approved provider identity/digest/scope boundaries and modified operations require reapproval. Inspect the dependency graph as well as executing tests.
- [ ] Commit after review: `Decouple app workflows from the plugin host`.

## Task 6: Native plugin views, activities, actions and generated forms

**Files:** create target `PluginUI` with `PluginViewRenderer.swift`, `PluginFormRenderer.swift`, `PluginActivityStore.swift`; create `LedgeApp/App/HostConnectionStore.swift`; replace `AutomationNotchView` in AppEnvironment and move infrastructure composition to `PluginComposition.swift`.

**Interfaces:** `PluginViewRenderer(presentation:dispatch:)`, `PluginFormRenderer(schema:uiSchema:draft:onChange:)`; `PluginActivityStore.accept(_:lease:) throws` enforces revisions, bounds and coalescing. Actions dispatch `PluginActionRequest` through Task 5, never an unvalidated shell or stale URL handler.

- [ ] Write renderer/form fixtures for all supported nodes, unknown nodes, malformed UTF-8/JSON, oversize trees/images, stale revisions, 5/s per-instance and 10/s global visible updates, 1/s hidden updates, long lists, keyboard navigation, VoiceOver and malicious markdown/URLs. Assert permission chrome and host navigation cannot be supplied by plugins.
- [ ] Run focused `PluginUI` tests and accessibility UI tests, expecting missing renderer/form behavior to fail.
- [ ] Implement native rendering, managed asset handles, timestamp-driven progress and coalescing. Generate pins/navigation from enabled instances only; render the last-successful stored snapshot after command exit with checked/stale timestamps, and clear transient overlays on failed lease. Keep config JSON and forms bound to one canonical validated document with atomic apply/diff.
- [ ] Verify in an actual panel: hover never steals focus; forms work after explicit invoke; disable removes navigation instantly; keyboard/VoiceOver match pointer actions. Snapshot tests supplement, not replace, those interactions.
- [ ] Commit after review: `Render native plugin apps and configuration forms`.

## Task 7: Offline app library and setup lifecycle

**Files:** create `LedgeApp/Library/AppLibraryStore.swift`, `AppLibraryView.swift`, `PluginSetupView.swift`, `FirstPartyApps/catalog.json`; modify Settings/Onboarding and CLI destinations; test `LedgeUITests/AppLibraryUITests.swift`.

**Interfaces:** `AppLibraryStore` consumes Task 4 lifecycle and Task 5 health, exposes available/installed/instances/connections/prerequisites; `PluginSetupDraft` holds config, schedule and connection references without credentials.

- [ ] Write `emptyInstallHasZeroAppsAndNoPermissionPrompts`, `offlineCatalogWorksWithoutAgent`, `installDoesNotEnableOrConnect`, `unavailableRuntimeHasActionableSetup`, `cancelSetupPreservesDisabledInstall`, `newGrantNeedsConsent`, and `twoNamedInstancesUseDifferentSchedules`.
- [ ] Run library/setup UI tests and verify the old raw-JSON Automations tab does not satisfy these flows.
- [ ] Build Discover/Installed/Connections/Developer sections, explicit source/trust/grant/runtime review and form-driven setup. Show signed-agent prerequisites honestly; local library/fixtures remain usable if agent unavailable. Provide an empty “Install Apps” state with no fixed feature controls.
- [ ] Complete install → configure → enable → pause → disable → uninstall against a fixture app with network denied, then repeat with missing signing/runtime and no hotkey. Verify recovery still works.
- [ ] Commit after review: `Add optional apps library and explicit setup`.

## Task 8: Three first-party apps using only the public plugin contract

**Files:** create `FirstPartyApps/{github-opportunities,github-ci,command-result}/`; adapt existing `Examples/github-opportunities/*`, GitHubIntegration/provider metadata and catalog; test app fixture suites and `LedgeUITests/PluginLifecycleUITests.swift`.

**Interfaces:** consume v2 package/UI/instance/action contracts with no kernel changes per app. GitHub apps depend on one optional reviewed GitHub provider; Command Result executes explicitly selected absolute program/argument arrays, not code embedded in card payloads.

- [ ] Write fixture flows: quiet first GitHub baseline; one new eligible issue; incomplete evidence held; revalidate before current-opportunity action; no duplicate after restart/config tweak; CI run transitions and rate-limit backoff; Command Result nonzero exit/timeout/cancellation. Verify two GitHub instances never exchange records and share only the approved connection/provider budget.
- [ ] Run app fixtures through real subprocess/SDK channels, including the existing Python regression suite, and show any unimplemented action revalidation/caching/HTTP-level budgeting failures explicitly.
- [ ] Package the apps with declared configs/views/commands, finish conditional caching and HTTP-level rate/request limits, and preserve conservative GitHub eligibility. No default install, enabled cron, real token or shell hook is added.
- [ ] Install each package into an unchanged host binary, configure it through the UI and verify its compact/expanded content; remove it and prove all its workers/navigation disappear. Use fixture credentials first; live GitHub qualification requires a user-provided approved connection.
- [ ] Commit after review: `Ship selectable developer app packages`.

## Task 9: Developer SDK, preview and test workflow

**Files:** modify `SDKs/python`, `SDKs/typescript`, `LedgeCLI/main.swift`, `Schemas`; create `Examples/hello-app/`, fixture hosts and `docs/developer/plugin-apps.md`.

**Interfaces:** `ledge init DIR`, `ledge validate DIR`, `ledge dev DIR --fixture FILE`, `ledge test DIR`, `ledge app install|list|disable|uninstall`, `ledge ui open --instance ID`; preserve documented legacy CLI aliases via v1 adapter. Development reload is explicit and prompts again for expanded grants.

- [ ] Write subprocess tests where a fresh template publishes a native view, handles arguments, stages state/result, rejects missing fixture integration data, and previews updates without an installation. Add a service fixture exercising ready/action/checkpoint/reply, lost receipt replay and graceful stop. Assert fixture mode cannot silently access live accounts and dry-run warnings describe independent script side effects.
- [ ] Run Python, Node and CLI fixtures with network disabled; expect missing v2 SDK/commands to fail.
- [ ] Implement version negotiation, rendering preview through the real host renderer, deterministic tests, explicit development reload and structured redacted logs. Resolve installed GUI location rather than assuming every build lives at `/Applications/Ledge.app`.
- [ ] Verify a developer can create/configure/preview/install a new app without touching Swift, editing host code or rebuilding Ledge. Do not auto-edit shell/agent hooks; document explicit CLI completion integration.
- [ ] Commit after review: `Add end-to-end plugin app development tools`.

## Task 10: Migrate, remove old feature composition and qualify distribution

**Files:** create `AutomationStorage/PluginMigrationJournal.swift`; modify AppDelegate/AppEnvironment/AppCoordinator, existing settings and package dependencies; update `Scripts/build-helpers.sh`, `verify-public-apis.sh`, coverage/CI, distribution docs and real acceptance tests. Remove obsolete fixed feature routes/views/menu helpers from the host target, preserving reusable broker/storage code and old data.

**Interfaces:** `PluginMigrationJournal.preview(source:) -> MigrationPreview`; `apply(_ preview:)` and recovery receipt preserve source and v1 job/event identity. Legacy feature settings become recommendations only; v1 jobs migrate paused pending explicit review.

- [ ] Write interrupted/resumed migration fixtures with existing jobs, unread/delivered events, clipboard/capture files, missing/locked key, both old/new roots, retired menu preference and absent optional app. Assert originals unchanged, no repeat alerts, no auto-install/enable/grant, no swallowed errors and no fixed UI feature routes after migration.
- [ ] Run fault-injected migration tests and dependency/source checks. Expected failures must identify each remaining legacy entry point before removal.
- [ ] Implement copy-first migration/recovery; update exact nested-code inventory/signing for official package workers and verify identifiers/Team IDs. A Developer ID-signed app/agent/CLI and notarized distribution are release prerequisites; label unsigned builds as development previews rather than disabling trust checks.
- [ ] Run full package/SDK/app/UI/performance tests, weighted per-product coverage gates, source/license/bundle scans, and clean-Mac signed install/enable/restart/stop/uninstall. Test physical notch/notchless/external, display disconnect, full-screen, sleep/wake, no-agent and keyboard-only recovery. Measure hidden idle wakeups/memory and p95 shell latency; report passing, failing, blocked and unrun evidence separately.
- [ ] Commit after review: `Migrate to the plugin-only notch host`. Do not ship until the real acceptance checklist passes; the earlier UI-runner authentication and low-coverage failures remain blockers until resolved.

## Milestone gates and handoff

- **Shell gate (Tasks 0–2):** no menu icon on old/new preferences; empty notch and recovery work with zero plugins and no agent.
- **Framework gate (Tasks 3–7):** a tiny optional app installs/configures/updates/disables/uninstalls via the real renderer without changing the host binary; no feature-specific dependency in the kernel.
- **Developer workflow gate (Tasks 8–9):** three selectable apps plus a new SDK-created app work end-to-end with fixtures; signed live GitHub remains a separate acceptance run.
- **Release gate (Task 10):** copy-safe migration, signing, UI/hardware, lifecycle, coverage, energy and accessibility qualify the installed build. Porting every old optional feature is not required to pass the framework gate.

Plan self-review: design §§1–4 map to Tasks 0–2/6/7; §§5–8 map to Tasks 3–6/9; §9 maps to Task 8; §10 maps to Tasks 0/4/10. Review Focus cases have concrete tests in their owning tasks. Shared identities/actions are defined in Task 3 and reused by name; batch and service lifecycles remain distinct. Proposed defaults require product review before implementation.

Fresh builder check raised two build-shaping gaps: persistent views after short command exit and durable checkpoints for live services. Both are now specified in design §6 and Tasks 3–6/9. The reviewer found no further material contradiction after those decisions. This is a document review, not software verification.
