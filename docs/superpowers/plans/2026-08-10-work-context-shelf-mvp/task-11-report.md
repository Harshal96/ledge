# Task 11 report: Settings, onboarding, and recovery

## Delivered

- Added a feature-scoped `AppCapabilityState`; Calendar, Screen Recording, Clipboard, and Audio states are independent, while shell, handoff, quick capture, and recovery remain available when a gated service is denied.
- Added a `PermissionCenter` with injected requesters for denial tests. Its initializer reads only a non-sensitive onboarding preference; consent APIs run only from explicit Settings actions.
- Added one-page, dismissible onboarding and native SwiftUI Settings tabs for General, Privacy, Storage, Shortcuts, and Diagnostics. Primary actions have visible labels, keyboard defaults, hints, and 44-point targets.
- Added `LoginItemController` around public `SMAppService.mainApp`; approval opens Login Items settings and registration errors leave the app usable. No helper executable is installed.
- Added explicit storage recovery controls and redacted JSON diagnostics. Delete All removes the Keychain master key first, then Ledge-owned files/preferences; macOS permission decisions are left untouched and the UI does not claim physical secure erase.
- Added package permission-isolation tests and launch/accessibility UI test fixtures.

## Validation

- `swiftc -parse` passed for all touched app, package, and UI-test Swift files.
- `plutil -lint` passed for the Xcode project and app Info.plist.
- `zsh Scripts/verify-public-apis.sh` passed.
- Full Swift/Xcode execution remains blocked in this checkout because only Command Line Tools are selected and their SDK/compiler revisions are incompatible; `xcodebuild` is unavailable.

## Runtime follow-up

- Re-run `swift test --package-path Packages/LedgeKit --filter PermissionPresentationTests` and the onboarding/accessibility/recovery Xcode UI tests with Xcode 16.3+ and a writable module cache.
