# Public API boundaries

Ledge's developer edition is a directly distributed, non-App-Sandbox macOS app with a separately signed user LaunchAgent and CLI. It uses public system APIs. The host's GitHub broker makes explicitly authorized read-only requests; local plugins are trusted native programs and can independently use their user's permissions.

- The app does not claim universal Now Playing metadata or playback control.
- The app does not promise global microphone mute; any future audio control is limited to public, capability-probed input-device controls.
- Clipboard source-app exclusions are best effort because pasteboard APIs do not provide a trustworthy source application identity.
- No private frameworks, private symbols, accessibility automation, or Apple Events are used. The exact embedded executable allowlist is `Ledge`, `LedgeAgent`, and `ledge-cli`. Agent registration uses ServiceManagement after an explicit user action; private pipes and signed XPC provide transport, not a sandbox for plugins.
- GitHub tokens remain in Keychain and are not provided through plugin APIs. The broker restricts repositories and operations, bounds response size, serializes requests, and rejects redirects.
- Release code-signing trust, notarization, and live service/credential behavior require signed-installation qualification; passing the static scan alone proves none of them.

The public-API scan is a release gate, supplemented by source and dependency review.
