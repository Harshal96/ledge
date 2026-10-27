# Ledge

A native macOS notch framework for apps you choose. No menu-bar icon, fixed feature tabs, or pre-enabled workflows. The notch surfaces a useful action and gets out of the way; a normal Apps Library window handles setup and recovery.

## Current implementation preview

- A public-AppKit notch/virtual-island shell with hover dwell, explicit keyboard opening, reduced-motion support, display selection, and presentation-safe suppression.
- An offline optional catalog: GitHub Opportunities, GitHub CI Watch, and Command Result. Browsing installs nothing; installation runs nothing; new instances start disabled.
- Trusted local Python/Node programs, validated v2 manifests, multiple configured instances, cron/interval schedules, encrypted transactional state/events, and persistent host-rendered views.
- Native configuration forms and bounded declarative UI. Plugins do not inject SwiftUI, HTML, windows, or libraries into Ledge.
- Disable/uninstall revocation, package-content pinning, stale-action rejection, per-instance notification policy, and explicit destructive-command confirmation.
- CLI and Python/TypeScript SDKs; fixture previews require neither GitHub credentials nor a registered agent.

This is **not a qualified signed release or the complete platform design**. Long-lived service workers, native OS brokers, provider-package installation, transactional package updates/archive restoration, and complete v1-to-instance migration remain unfinished. Existing capture/clipboard/audio/calendar/handoff code is inactive in the production GUI; these are not built-in features or available plugin apps yet. See the [current status](docs/superpowers/plans/2026-10-26-notch-plugin-shell-progress.md).

## Use and recovery

Open the app in Finder/Spotlight to reach Apps Library. The default global shortcut is Command–Option–Space; Developer settings can change it to K or L, choose a display, reset placement, or enable presentation-safe mode. There is deliberately no status-item recovery dropdown.

The production agent requires matching Apple signing identities for the GUI, agent and CLI. An unsigned build can browse the offline catalog but does not establish working background automations. Registration, connections and enablement are separate explicit steps. Nothing is installed into `/Applications` by a source build.

Start with the [developer quickstart](docs/developer/quickstart.md).

## Trust and privacy

Local code runs with your macOS user permissions. Host grants constrain host APIs, **not** a script's independent filesystem or network access. Review code before trusting it. Preview mode does not sandbox arbitrary code; Command Result's own preview deliberately skips its external executable.

The host owns credentials in Keychain and exposes scoped operations, not tokens. GitHub read operations remain an explicitly composed provider; arbitrary third-party connection-provider packages are not supported yet. No analytics, automatic dependency installation, cloud runner, plugin download or unauthenticated local HTTP API is introduced.

Legacy data is retained. Old schedules are paused once with encrypted definition metadata saved before the new host starts. This safeguard is not the complete copy-first migration or a restore/export UI. Older v1 package integrity metadata requires a reviewed new version before execution; state/event identities are not deleted.

## Development

Use a matching full Xcode/macOS SDK toolchain:

```sh
swift test --package-path Packages/LedgeKit
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=SDKs/python python3 -m unittest discover -s FirstPartyApps/tests -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s SDKs/python/tests -v
npm test --prefix SDKs/typescript
xcodebuild -project Ledge.xcodeproj -scheme Ledge -configuration Release build CODE_SIGNING_ALLOWED=NO
./Scripts/verify-public-apis.sh
```

The checkout's agent instructions require `rtk` command prefixes. Package tests and compilation are not evidence of installed UI behavior, real display/focus/accessibility performance, battery usage, signed IPC, or live GitHub success.

Read the [approved design](docs/superpowers/specs/2026-10-26-notch-plugin-shell-design.md), [implementation plan](docs/superpowers/plans/2026-10-26-notch-plugin-shell-implementation.md), and [public API boundary](docs/architecture/public-api-boundaries.md).
