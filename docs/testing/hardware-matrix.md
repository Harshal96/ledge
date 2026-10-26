# Hardware and permission matrix

This is the release test sheet, not a claim that every row has been exercised in this checkout. Each row needs a pass/fail result, OS/build, display/device topology, and a short evidence reference before a store candidate is declared.

| Area | Required scenarios |
| --- | --- |
| Displays | Notched internal, notchless Mac, one/two/three displays, menu bar moved, negative coordinates, Retina/non-Retina, extended, mirrored, hot unplug while peek/expanded/importing |
| Windowing | Spaces, Stage Manager, another app full-screen with menu bar shown/hidden, display disconnect and reconnect |
| Accessibility | Reduce Motion, Reduce Transparency, Increase Contrast, 200% text, VoiceOver names/order, keyboard-only completion, 44-point primary targets |
| Power/session | Sleep/wake, lock/unlock, clock/time-zone jump, clipboard pause/resume, launch after force quit |
| Permissions | Calendar not determined/denied/revoked, Screen Recording not determined/denied/revoked, pasteboard denied/paused, unrelated flows remain available |
| Audio | Built-in, USB, Bluetooth, HDMI/AirPlay, device removal, read-only volume, unsupported input mute; write tests are local-only and restore state |
| Storage | Disk-full simulation, locked/unavailable Keychain, corrupt envelope, interrupted import/export, 1 GiB handoff boundary, expired cleanup after relaunch |

The test/build baseline uses the currently selected Xcode (`xcode-select -p`), not a machine-specific Xcode path. Automated package and Xcode test results must be recorded separately. Registration of a test target or existence of test source is not proof that tests executed; CI requires an xcresult summary with at least one passed test. The coverage gate uses file-level covered/executable line counts for each product target, with an 80% floor per target. It excludes `.xctest` bundles only, because those are test code rather than product code.

All hardware, permission and signed LaunchAgent rows remain pending until run on the corresponding real topology/profile. An Xcode build, fixture test or simulator run cannot qualify them.
