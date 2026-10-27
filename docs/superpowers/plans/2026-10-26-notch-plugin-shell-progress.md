# Notch plugin shell: implementation status

## Hover-only follow-up (2026-10-27, after 9d8cf1e)

The user reported that the hotkey opened Ledge but hover did not, and explicitly requested no hotkeys because the chord also opens macOS search. Production AppDelegate no longer constructs/registers Carbon hotkeys, reads the old shortcut preference, or exposes shortcut controls/hints. Finder/Spotlight reopen remains recovery. The shared legacy hotkey utility is inactive, not registered by the new entry point.

Geometry regressions reproduced the hit-area miss: the old trigger only covered six pixels below the housing/menu safe area, missing the camera housing and actual screen top. The trigger now covers the housing plus six pixels below on notched displays, or a top-center six-pixel strip on notchless displays. Its public window level is above the status bar while constrained to that band; content remains below the camera. Tests failed before the geometry fix and passed afterward. Full suite: 22 XCTest + 102 Swift Testing passed; Release build passed. No direct visual/physical hover claim: computer-use access to Ledge was not approved. The installed running app remains unchanged pending user quit/replacement; these changes are not yet committed or pushed.

Installation follow-up: after the user confirmed quitting, the hover-only build was installed at `/Applications/Ledge.app`. The prior bundle is preserved at `/Applications/.Ledge-backup-before-hover-only.app`. Installed and built GUI SHA-256 hashes matched, and strict recursive signature verification passed. The app was not opened through an alternative UI mechanism after computer-use denial; physical hover behavior remains unconfirmed. This follow-up is now included in the user's requested commit/push.

The sections below record the earlier implementation preview based on `40593c2` (committed as `9d8cf1e`), before the hover-only follow-up. The approved [design](../specs/2026-10-26-notch-plugin-shell-design.md) remains broader than this implementation.

## Delivered in source

The production entry point no longer constructs the status item or legacy feature services. `StatusItemController` is deleted. Its framework/project dependencies no longer select Audio/Capture/Clipboard/Meetings/Handoff workflows. The inactive legacy sources and user data are retained for compatibility; removing the old launch composition is not the same as packaging those workflows as apps.

The new `NotchWindowCoordinator` has one presentation state machine, hover/exit deadlines, nonactivating automatic presentation, explicit keyboard opening, public safe-area placement, reduced-motion handling, selected-screen fallback and pointer-on-explicit-open. Apps Library/Finder reopen remains independent of the background runner. Developer controls configure the hotkey, display, reset and presentation-safe mode. Full-screen suppression is conservative; real-display behavior is not yet qualified.

V2 contracts cover manifests, installations, multiple instances, commands/arguments, snapshots, leases, checkpoint receipts and bounded native trees. The host installs packages only after trust, stages content, rejects symlinks/special files, pins a length-framed SHA-256 digest, and defaults new instances to disabled. Disable and uninstall revoke active leases; configuration revision and control-epoch checks prevent stale invocations. Commands commit state/records/events/views only after successful protocol completion and exit. Last-successful views survive process exit and restart.

Apps Library provides Discover, Installed, Connections and Developer sections, validated configuration forms/advanced JSON, schedules, pins, enablement and retain/delete uninstall choices. The notch lists enabled instances rather than fixed feature tabs. Command actions are validated/confirmed; explicit event links are resolved by current instance ownership/revision and reject disabled apps. Delivery observes preferences, freshness and peek budgets. A failed quit-stop is surfaced for an explicit decision.

Three optional catalog apps are supplied: GitHub Opportunities (conservative scanner plus action-time recheck), GitHub CI Watch (quiet baseline/deduplicated completion) and Command Result (explicit executable/argv, no shell interpolation). No package or instance is installed/enabled by browsing. The CLI creates Python/Node v2 templates, validates/previews fixture-backed programs, installs/configures/disables/removes instances, and opens the containing app without a hard-coded installation path. Both SDKs expose authoritative `stateRevision` for monotonic snapshots.

## Verification performed

| Check | Result |
| --- | --- |
| `swift test --package-path Packages/LedgeKit` | 22 XCTest + 101 Swift Testing tests passed; full output `.build/notch-suite.log` |
| Python SDK unittest suite | 4 passed, including actual bidirectional subprocess protocol |
| First-party offline unittest suite | 4 passed: preview isolation, CI baseline/dedup/partial partition, issue recheck |
| TypeScript SDK subprocess/context tests | 2 passed |
| Built Release CLI previews | CI baseline, command preview, closed-issue recheck passed against fixtures; native snapshots at revision 8 from stateRevision 7 |
| Release Xcode build with signing disabled | Passed, including bundled GUI/agent/CLI/SDK/catalog; `.build/notch-app-build.log` |
| Public API scan / third-party license gate | Passed |
| Status-item/legacy feature launch-path source search | No matches in production app/shell/plugin UI |
| Generated SDK/app resource cache scan | No `.pyc` or `__pycache__` in the product resources |
| Diff whitespace check | Passed |
| New UI automation | Did not reach assertions: UI test runner killed before establishing connection; not a behavioral pass |
| Signed lifecycle / real GitHub / physical display / accessibility / energy | Not qualified; no account connection or system service registration performed |
| Coverage release gate | Existing 1.28% baseline is below the required 80%; not waived or represented as current coverage |

The generated build includes `40593c2-dirty` provenance and the running executable path. The existing installed `/Applications/Ledge.app` was not replaced or started by this implementation pass.

## Review fixes

A fresh source review found six Important issues, all addressed with regressions in the fix pass:

1. New IDs could inherit legacy/archived data. Cross-namespace identity reservation now denies this in both directions.
2. Disable could fail if a package/schema changed. An independent disable operation revokes execution without reopening the package.
3. Retain-data uninstall discarded last-successful views. Views/checkpoint receipts now remain encrypted and inactive.
4. Equal/older snapshot revisions could overwrite a successful view. Durable commits now require strictly increasing revisions.
5. Default Run/scheduling could bypass destructive confirmation. All manual routes require approval; destructive defaults cannot be scheduled.
6. Quit skipped stop when cached connection state was false and discarded failures. Stop is always attempted unless keep-running was explicitly chosen; failures require a decision.

Additional regressions reproduced and fixed: stale-config/stop-before-registration races; ambiguous filename/content concatenation in package hashes; hidden legacy schedules starting behind the new empty library; CI partially emitting from an incomplete repository; wall-clock-derived snapshot regressions; unavailable CI event-link dispatch. Tests were observed failing before their fixes. The final complete package suite passed after those changes.

## Rulings and costs

- Work in the existing feature checkout rather than another worktree: preserves the approved project context; costs additional isolation, mitigated by narrow patches.
- Do not infer commit/push/install/account/registration authority from plan prose: keeps source reviewable; the installed preview remains unchanged until a separate distribution action.
- Keep inactive v1 types/storage/UI source for compatibility: preserves data and clients; costs obsolete code and replacement of old fixture UI tests before release.
- Add app tables to the agent-owned encrypted database: keeps one state owner; costs a real versioned/copy-first migration before release.
- Pause old schedules once and retain encrypted original definitions without converting/deleting state/events: prevents invisible legacy execution; costs explicit review and unfinished conversion/restore UI.
- Use framed package hashing and require renewed review for old v1 weak-integrity metadata: prevents package-boundary ambiguity; costs installing a reviewed new version before old programs execute. Original metadata/state/event identities remain untouched.
- Treat service/broker/provider/update/migration work set aside by review as unfinished, not waived acceptance: unsupported services cannot enable; costs incomplete platform breadth until those tasks are implemented.
- Treat signing, UI-runner, display/focus, VoiceOver, energy and coverage as release blockers, not implied successes: compiled previews are useful for development only; costs deferring release claims.

## Remaining implementation and release gates

No task is marked wholly complete merely because its preview implementation compiles. Continue with these concrete gaps:

1. Task 5: distinct long-lived service session/ready/action/reply transport, 30-second heartbeat, checkpoint rate backpressure, failure pause/restart, lazy GUI OS brokers and disconnection semantics. Do not make command success durable before exit as a shortcut.
2. Tasks 5/7: generic installable provider packages and connection identity/digest/scope binding. GitHub is injected outside the kernel but still compiled; legacy `connect.github` compatibility and the GitHub connection editor remain. Provider caching/budgets/health need completion.
3. Tasks 4/10: explicit update staging, data-copy migration/rollback, archived instance restore/export, v1 paused-instance conversion and a real versioned migration journal. Current metadata pause is only a safeguard.
4. Tasks 2/6/7: interruption-safe collapse polish, full keyboard/VoiceOver acceptance, complete UI-schema/path/connection controls, managed-image rendering, compact multi-activity presentation, per-instance reorder/retention controls and bounded/paginated large snapshots.
5. Tasks 8/9: broader starter/scanner fixture matrix, SDK service fixtures, live development linking/reload and diagnostics tooling. The `test` CLI currently runs one fixture via the preview adapter.
6. Task 10: replace obsolete UI fixtures, resolve the UI runner bootstrap problem, meet coverage, measure actual idle/hotkey/energy behavior, test notched/notchless/external/full-screen hardware and qualify signed GUI/agent/CLI on a clean installation.

No real tokens, legacy data, installed app, shell hooks or system schedules were changed during verification. Test subprocesses and encrypted databases used temporary directories.
