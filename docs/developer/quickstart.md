# Build your own notch app

Ledge's production GUI is infrastructure only. An app is a trusted program plus a v2 manifest and optional JSON configuration schema. Users install the package, add one or more named instances, configure each, then explicitly enable it.

## Preview without an account or installation

From this repository with full Xcode selected:

```sh
swift run --package-path Packages/LedgeKit ledge validate FirstPartyApps/github-ci
swift run --package-path Packages/LedgeKit ledge dev FirstPartyApps/github-ci --fixture FirstPartyApps/github-ci/fixtures/baseline.json
swift run --package-path Packages/LedgeKit ledge dev FirstPartyApps/command-result --fixture FirstPartyApps/command-result/fixtures/preview.json
swift run --package-path Packages/LedgeKit ledge dev FirstPartyApps/github-opportunities --command review --fixture FirstPartyApps/github-opportunities/fixtures/review-closed.json
```

These run actual local programs against fixture host responses and print their native view payloads. They do not contact live integrations, persist host events, register launchd or show notifications. Missing fixture responses fail closed. Any independently coded script side effects remain possible: fixture mode is not a sandbox.

The contribution scanner starts with a quiet baseline by default. It treats incomplete assignment/comments/PR evidence as unknown, requires configured trusted repository triage evidence, deduplicates alerts, and rechecks eligibility when a user invokes Review. The old v1 example and its fixtures remain under `Examples/github-opportunities`; it is not installed by browsing the catalog.

## Create a package

```sh
swift run --package-path Packages/LedgeKit ledge init /tmp/my-ledge-app
swift run --package-path Packages/LedgeKit ledge dev /tmp/my-ledge-app
# Or create a source-only Node program:
swift run --package-path Packages/LedgeKit ledge init /tmp/my-node-app --language typescript
```

Choose a new directory: init never overwrites one. The Node template emits `.mjs`, which runs directly without installing a TypeScript compiler. The typed SDK lives in `SDKs/typescript` and its source tests require Node 24+. Use `--interpreter /absolute/path` for NVM/custom runtimes. Python's SDK lives in `SDKs/python` and is bundled with the app. Package your dependencies yourself; Ledge runs no npm/pip/setup hooks.

The short-lived command protocol is newline JSON-RPC over private pipes. Host input includes `automationID`, `command`, validated `arguments`, `config`, authoritative `state`, monotonic `stateRevision`, mode and time. Return one successful final result and exit zero; only then can state, records, events and `viewSnapshot` commit together. Failed/timed-out commands leave the previous successful snapshot intact. Use `stateRevision + 1` for a new snapshot revision, not wall-clock time.

See the starter manifests and `AutomationDomain/PluginViewContracts.swift` for the supported bounded view tree. No raw HTML, arbitrary image path, shell string action or in-process plugin UI is accepted. Destructive commands require confirmation and cannot be scheduled as an unattended default.

## Run on a signed installation

The app bundle has three executables: `Ledge`, `LedgeAgent`, and `ledge-cli` (the latter avoids a case-insensitive collision with `Ledge`). An unsigned Release build proves compilation only. Production IPC requires matching Apple signing Team IDs and expected identifiers; no release-mode development bypass is added.

Open Ledge → Apps Library. Discover is offline and works without the agent. Developer → Enable signed background runner explicitly registers the service, potentially requiring macOS Login Items approval. Install an app, add an instance and save configuration; enable it only when ready. The equivalent CLI operations are:

```sh
ledge app install /absolute/path/to/app --trust-local-code
ledge app list
ledge app configure /absolute/path/to/instance.json
ledge app disable INSTANCE_ID
ledge app uninstall PACKAGE_ID                 # retains data
ledge app uninstall PACKAGE_ID --delete-data   # explicit deletion
ledge stop
ledge resume
```

`app list` returns canonical instances suitable for editing/export. `configure` accepts a complete instance document; preserve its identity/revision rather than inventing an old ID. New instances start disabled even if input requests enablement. Retained archives cannot execute and do not restore themselves on reinstall; a restoration workflow is unfinished.

Hover over the camera housing/top-center edge to open the notch. No global hotkey is registered. Finder/Spotlight reopen reaches Library independently. Closing a window leaves the process resident; standard Quit requests Stop unless Keep running is explicitly chosen. A failed stop asks for retry/keep-open/explicit quit-anyway instead of claiming work stopped.

## GitHub

Install an app declaring the GitHub dependency, then use Connections' secure token field or `ledge connect github --name personal --token-stdin`. Tokens belong in Keychain, never plugin config, arguments or source. Set the instance's connection name and explicit repository list. Only fixed read operations are exposed; redirects are disabled.

GitHub is currently a compiled provider behind a generic interface, not yet a separately installable connection extension. Live-account, signed-agent and actual notch delivery qualification remain open. Service manifests can be inspected/installed but cannot be enabled until the separate supervised service adapter is implemented; high-frequency cron is not a substitute.

## Limits and release status

256 KiB frames, 2 MiB child output per invocation, bounded command timeouts, 64 KiB state, 16 KiB records, bounded native trees, per-instance grants/leases, and transactional commits constrain host use. They do not contain malicious trusted-user native code.

Generated forms cover the bounded configuration subset; full UI schema/path/connection controls, managed-image rendering, live development reload, service workers, native brokers, provider-package lifecycle, package update rollback and complete migration are unfinished. See the [implementation status](../superpowers/plans/2026-10-26-notch-plugin-shell-progress.md) before distributing or enabling important workflows.
