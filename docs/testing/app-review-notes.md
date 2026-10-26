# Distribution and permission notes

The current developer edition is intended for direct distribution, not Mac App Store submission. It is not App Sandbox-compatible: explicitly trusted Python/Node/shell programs run as the user. A signed ServiceManagement LaunchAgent owns scheduling, encrypted state/inbox, integration credentials, and child processes. No analytics, cloud sync, updater, automatic plugin download, or remote feature flag is present. These notes supersede the earlier sandboxed MVP assumptions.

## Permission prompts

- Calendar is requested only after the user enables Meetings. The app reads a bounded upcoming-event interval and keeps event details in memory.
- Screen Recording is requested only after the user chooses Capture Screenshot. The selected region is captured with ScreenCaptureKit, Ledge is excluded, and the PNG is stored through the encrypted repository.
- Clipboard monitoring is off by default. Opt-in explains pasteboard access, best-effort frontmost-app exclusions, pause, retention, and Clear All before monitoring begins.
- No Accessibility, Input Monitoring, Automation, Contacts, Bluetooth, microphone capture, or network entitlement is required.

## Recovery and privacy

The optional recovery status item exposes Open Shelf, Settings, Reset Shelf Position, and Quit. The global hotkey and Finder reopen provide recovery without a toolbar item. Denied or revoked feature permissions do not disable unrelated capture, storage, handoff, or recovery flows.

Handoff “Move from shelf” deletes only Ledge's managed copy after a verified export; it never deletes the original source file. QR is offline and accepts only text/HTTP(S) URLs. The app does not claim universal cross-app Now Playing because the public MediaPlayer APIs do not provide that reader/control surface.

## Reviewer checks

1. Launch/reopen the app and open Settings without granting Calendar or Screen Recording permission; also test the optional recovery icon.
2. Enable Meetings, Screenshot, and Clipboard one at a time and observe the just-in-time explanations and denial recovery.
3. Use the hotkey on a notched display, notchless display, and external display; press Escape and disconnect a display while the shelf is visible.
4. Drop a text item and a bounded file, export a copy, then use Move from shelf and verify only the managed shelf copy is removed.
5. Run the public-API and license scans; inspect the archive for exactly the three allowed executables and approved system frameworks.
6. Qualify agent registration, matching signing requirements, stop/restart, Keychain credential handling, process teardown, and notarization on a signed installation before release. No such live-installation qualification is implied by an unsigned build.
