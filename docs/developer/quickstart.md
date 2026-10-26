# Developer automation quickstart

## Try a plugin without installing or connecting anything

From the repository root, with full Xcode selected:

```sh
swift run --package-path Packages/LedgeKit ledge validate Examples/github-opportunities
swift run --package-path Packages/LedgeKit ledge dev Examples/github-opportunities --fixture Examples/github-opportunities/fixtures/new-match.json
```

The second command runs the actual Python plugin with fixture-backed host calls and prints one native-card payload. It does not access GitHub, persist events, register launchd, or display a notification. `owner/repo` is deliberately a placeholder. The default first live scan quietly baselines existing issues. Incomplete assignment/PR/triage evidence holds a candidate rather than recommending it.

Create a minimal program:

```sh
swift run --package-path Packages/LedgeKit ledge init /tmp/my-ledge-plugin
swift run --package-path Packages/LedgeKit ledge dev /tmp/my-ledge-plugin
```

Choose a new directory; init will not overwrite one. Python's SDK is in `SDKs/python`; TypeScript's is in `SDKs/typescript` (Node 24+ for the source-only fixture test). Production plugins should package their dependencies; Ledge never downloads dependencies or executes install hooks. Use `--interpreter /absolute/path` when your runtime is outside common system/Homebrew locations, including NVM installations.

## Native app and background agent

Build the Ledge Xcode scheme. The app bundle contains three distinct executables: `Ledge`, `LedgeAgent`, and `ledge-cli`. The CLI is named `ledge-cli` inside the bundle because `Ledge` and `ledge` collide on case-insensitive macOS volumes. You can create your own shell alias to that executable.

The production XPC boundary requires the app, agent, and CLI to carry matching Apple signing Team IDs and the expected bundle identifiers. An unsigned Release build demonstrates compilation only; it is not a functional signed installation. Debug development may explicitly opt into `LEDGE_DEVELOPMENT_IPC=1` in both processes; that same-user development channel is not release security qualification.

Open Ledge, hover at the camera housing/top edge, and open Settings → Automations. Enable the background service explicitly. macOS may require approval in Login Items. No service is registered merely by building or running fixture tests. Review local code before installing it.

For a properly signed installation, the equivalent CLI workflow is:

```sh
ledge plugin install /absolute/path/to/plugin --trust-local-code
ledge automation apply /absolute/path/to/ledge.json
ledge status
ledge run JOB_ID --dry-run
ledge runs
ledge events
ledge stop
ledge resume
```

`automation apply` validates all submitted jobs before upserting them; omitted jobs are not silently deleted. Example jobs default to disabled. Turn a job on intentionally after configuring it. Stop persists across agent restart and cancels supported cooperative invocations; deliberately detached hostile programs are outside the trust model. Closing the interface leaves the agent alone; standard Quit stops scheduled work unless you explicitly choose to keep it running.

## GitHub connection

Use the secure token field in Automations settings or `ledge connect github --name personal --token-stdin`. Never put a token in config, plugin code, command arguments, or version control. Configure the automation's `connection` to that name and explicitly list repositories. The broker permits only fixed read operations against those repositories; redirects are disabled. Configure trusted triage labels or trusted maintainer handles per repository rather than assuming every `good first issue` is ready for contribution.

No real account was connected during implementation verification. The live API, token permissions, signing, and notch delivery still need end-to-end qualification on the target installation.

## Current limits

The current editor uses validated JSON, not the full planned generated configuration forms. Cards use a bounded host-owned detail format. Advanced retention/tombstones, provider conditional caching, persisted retry/health policies, affected-repository-only config reconciliation, action-time GitHub revalidation, snooze/save/ignore, live development linking, and OS-notification fallback are not complete. Do not treat the preview as a 24/7 hosted runner or as a sandbox for untrusted plugins.
