# Ledge

Ledge is a local-first, notch-first developer work-context shelf. Trusted local programs run on a schedule and publish native cards; the notch briefly surfaces the next useful action, then disappears. A hotkey, Finder reopen, settings window, and optional recovery icon keep the app accessible.

## Developer automation preview

The repository now includes a background agent, CLI, versioned local-plugin manifests, bounded JSON-RPC over private pipes, encrypted transactional state/inbox, timezone-aware cron and interval scheduling, Python and TypeScript SDKs, and a read-only GitHub contribution-watcher example. The GUI exposes automation settings and a notch inbox; it does not load plugin UI code.

Start with the [developer quickstart](docs/developer/quickstart.md). This is an implementation preview, **not a qualified signed release**. Live GitHub, signed agent registration/XPC, physical-display behavior, UI automation, and coverage thresholds remain release gates. See the [implementation ledger](docs/superpowers/plans/2026-10-26-developer-automation-platform-progress.md) for exact status.

Local plugins run with your macOS user permissions. Host capability checks restrict the host APIs, not native code's independent filesystem or network access. Review plugins before granting trust; a dry run suppresses host commits, not arbitrary script side effects.

## MVP

- Adaptive notch/notchless/external-display shell using public AppKit geometry.
- Top-edge black pill shell that expands on hover into the next-action card, then stays out of the way.
- Keyboard quick capture for notes, tasks, links, and permission-gated screenshots.
- Encrypted local shelf records with expiry and crash reconciliation.
- Opt-in, privacy-safe clipboard text/URL shelf with search, favorites, exclusions, and pause.
- Next-meeting countdown and join card after explicit Calendar access, with manual presentation-safe redaction.
- A real handoff tray for text, URLs, screenshots, and bounded file copies, including expiry, copy/move-from-shelf, Share/AirDrop, and offline QR for text/URLs.
- Capability-aware public Core Audio output, volume, and input-device mute controls. Universal cross-app Now Playing is intentionally not claimed because macOS does not provide that through the public APIs used here.

Shelf data stays on this Mac. There is no cloud sync, analytics, remote flag, updater, local HTTP server, or automatic plugin download. GitHub automation is explicitly connected by the user; its credentials live in Keychain and are not passed to plugins through host APIs.

## Privacy and scope

Permissions are requested just in time: Calendar when Meetings is enabled, Screen Recording only when Screenshot is invoked, and pasteboard monitoring only after an explicit opt-in. Clipboard source exclusions are best effort and fail closed before reading types or content. Handoff imports reject directories, symlinks, special files, oversized files, and traversal names; “move” deletes only Ledge's managed copy.

Deferred work includes weather, stocks, focus tools, window snapping, EQ, Android sharing, AI screen sharing, automatic presentation detection, OCR, video/audio capture, cloud sync, and a plugin marketplace. The developer edition is directly distributed and is not App Sandbox-compatible.

## Development

The package and app require Xcode 16.3+ with the macOS 15 SDK. From the repository root:

```sh
swift test --package-path Packages/LedgeKit
xcodebuild test -project Ledge.xcodeproj -scheme Ledge -destination 'platform=macOS'
./Scripts/verify-public-apis.sh
```

The local checkout may use `rtk` wrappers for these commands. If the installed Command Line Tools and SDK revisions do not match, runtime compilation cannot be treated as a green result; use the static parse, plist, project, and diff checks until the full Xcode toolchain is available.

See [the public API boundary](docs/architecture/public-api-boundaries.md), [testing matrix](docs/testing/hardware-matrix.md), and [App Review notes](docs/testing/app-review-notes.md) for release constraints.

## Developer platform design

The design remains broader than the current preview; it is not a claim that every planned capability has shipped:

- [Developer automation platform design](docs/superpowers/specs/2026-10-26-developer-automation-platform-design.md)
- [Phased implementation plan](docs/superpowers/plans/2026-10-26-developer-automation-platform.md)
