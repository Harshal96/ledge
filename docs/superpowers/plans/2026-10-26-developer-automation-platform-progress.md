# Implementation ledger — plan: 2026-10-26-developer-automation-platform.md

## Decisions

- Work in the existing checkout on `feat/developer-automation-platform`: all prior app files are uncommitted and must remain intact. No commits, installs, account connections, enabled schedules, or background registration without their own concrete workflow.
- Execute inline, with a fresh final reviewer. The versioned spec remains binding. Signing/notarization and physical-display qualification are release gates, not claims inferred from compilation.
- Pre-flight: domain → runtime/storage/IPC/UI contracts are shared. Implement domain contracts first; all subsequent modules consume them. Existing shelf IDs stay behind bundled adapters rather than expanding their closed enums.

## Implemented preview (26 October 2026)

This is a working source preview, not completion of the entire design or release qualification.

- Task 0: baseline established, release gates remain red. Real Xcode integration/UI/performance test targets and nonzero-test/coverage gates exist. Earlier Xcode execution ran 12 tests: 11 passed, UI-runner initialization failed with system-authentication cancellation. Coverage was 1.28%, below the required per-product 80%; neither result is waived. See the Task 0 report.
- Task 1: versioned manifests, strict duplicate-key JSON parsing, configuration/card/result limits and bounded plugin configuration-schema validation implemented. Full card union and generated forms remain incomplete.
- Task 2: dynamic notch geometry, below-housing expansion, hover delay/exit grace, hotkey/Finder recovery and optional menu icon implemented. Physical notch/notchless/external/full-screen qualification remains unrun.
- Task 3: encrypted SQLite jobs, leases, state, records, deduplicated inbox and delivery markers implemented with transactional completion. Retention, long-lived tombstones and versioned migration qualification remain incomplete.
- Task 4: ServiceManagement agent, Team-ID/identifier-checked XPC, CLI and explicit registration controls implemented. Unsigned Release builds fail closed for production IPC. Signed installation, credential sharing, restart and notarization remain unqualified.
- Task 5: pinned explicitly trusted plugin installation, process-group supervision, minimal environment, bounded bidirectional JSON-RPC and success-only commit implemented and exercised with actual child processes. Native code is not sandboxed. Broader hostile-descendant teardown is not promised.
- Task 6: five-field timezone-aware cron, interval anchoring, stable jitter, persisted due times, run-latest/skip policies, concurrency bounds and stop cancellation implemented. Persisted retry/health/backoff policy, exhaustive clock-jump/restart interleavings and wake qualification remain incomplete.
- Task 7: native notch inbox, detail cards, acknowledgment, delivery markers, quiet/privacy policy and peek limits implemented. OS fallback, snooze and all presentation modes remain incomplete/unqualified.
- Task 8: Keychain connections, fixed read-only GitHub operations, repository scoping, serialized requests, bounded bodies, denied redirects and incomplete-evidence handling implemented. Conditional caching, complete per-HTTP-request budgets and live GraphQL/token qualification remain open.
- Task 9: Python contribution watcher implements conservative eligibility, deterministic ranking, quiet baseline, checkpointed discovery, partial-coverage handling and deduplication. Daily reconciliation, affected-partition-only config changes, save/snooze/ignore and action-time revalidation remain open.
- Task 10: CLI validate/init/dev/install/apply/connect/run/history/events/stop/service commands and Python/TypeScript SDKs exist. Offline fixture preview works. Dedicated test/log commands and live development linking remain open.
- Task 11: real Settings/recovery window, service/credential/plugin controls and validated JSON editor implemented. Full schema-generated configuration UI remains open.
- Task 12: existing shelf features preserved; conservative copy-only migration path added. Bundled tools/static scans updated. Migration, universal architectures, signed release, energy, accessibility and physical-display qualification remain open.

## Verification evidence

- Swift package suite: 22 XCTest tests plus 82 Swift Testing tests passed, zero failures. Includes real plugin execution, bidirectional host-call round trip, timeout teardown, prelaunch cancellation gate, stopped-store late-commit rejection, encrypted SQLite restart/atomicity/deduplication, asymmetric-notch/external geometry, schema/cron/DST/jitter and broker numeric-boundary tests. Latest logs: `.build/platform-suite.log`.
- Python SDK: 3 tests passed. GitHub watcher: 7 tests passed, including unknown-to-pass quiet baseline. TypeScript SDK: 1 real protocol test passed.
- `ledge dev Examples/github-opportunities --fixture Examples/github-opportunities/fixtures/new-match.json` exited 0 and produced one ranked card through the real Python process and host-call channel. This is offline evidence, not live GitHub or notch-delivery qualification.
- The embedded Release `ledge-cli` also validated the example manifest/config and completed the same offline preview, confirming bundled Python SDK discovery without the Debug source fallback.
- Native arm64 Release app build with signing disabled exited 0. Bundle contains distinct `Ledge`, `LedgeAgent`, and `ledge-cli` binaries. No install or background registration was performed.
- Source public-API and third-party-license scans passed. Xcode test registration and five gate fixtures passed. These are separate checks; do not equate them with UI execution or coverage acceptance.

## Review rulings and implementation adjustments

- Read-only review identified numeric conversion traps, Stop-all prelaunch races, destructive configuration resets, late-baseline historical alerts and page-100 looping. Checked bounds, tracked/cancelled invocation tasks, configuration epochs, record preservation, delayed first-evaluation completion and unclamped bounded pagination address these findings. Full partition reconciliation remains open.
- Offline end-to-end testing exposed Foundation pipe buffering blocking bidirectional RPC. POSIX streaming reads fixed it; a focused test failed before and passed after the change.
- Follow-up review caught a narrower pre-spawn cancellation race. The invocation lock now orders cancellation with native spawn/PID registration; cancellation that wins cannot launch code. Cancellation is checked again after process completion and within the store transaction, which also rejects completion while stopped.
- Final focused reviewer inspection confirmed those safety findings resolved. Stop is not a rollback: native effects or transactions that won their ordering point before Stop can already have occurred, and supported process-group termination is cooperative rather than a guarantee about hostile detached descendants.
- `Ledge` and `ledge` collide on default case-insensitive macOS filesystems. The embedded CLI is deliberately **`ledge-cli`**, not the originally planned name; the SwiftPM product remains `ledge`.
- Agent and CLI source entrypoints live under the existing Swift package rather than separate root source targets. The LaunchAgent plist remains under `LedgeAgent/Resources`.
- Earlier docs describing a sandboxed single-process/no-network app are superseded by the direct-distribution developer edition documentation.
- No commit, installation, launchd registration, real token creation, real GitHub request or schedule enablement was performed during these verification steps.
