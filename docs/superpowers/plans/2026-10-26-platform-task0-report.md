# Task 0 platform/test baseline — 26 October 2026

Selected toolchain: Xcode 26.6 (17F113), macOS 26.6.2, Apple Silicon. This is a local development baseline, not a signed release or hardware qualification.

## Registered test execution

- `LedgeIntegrationTests`, `LedgeUITests`, and `LedgePerformanceTests` are real synchronized-source Xcode targets in the shared `Ledge` scheme. `Scripts/verify-test-targets.sh --project` passed after `xcodebuild -list` and `-showTestPlans`; the scheme has three enabled testables.
- The result-bundle gate reads `xcresulttool get test-results summary` and rejects missing, zero-test, all-skipped, or failed runs. Five gate fixture tests passed, including an intentionally empty `Passed` summary that is rejected.
- `rtk swift test --package-path Packages/LedgeKit` compiled and passed in `.build/platform-suite.log`: 22 XCTest tests and 70 Swift Testing tests, zero failures. Existing Swift 6 test-double isolation, argument-order, and fixture-initialization defects were repaired without dropping assertions. Two production defects exposed by this baseline (the audio write window and wrong-kind vault error) were fixed by the domain owner.
- `rtk xcodebuild test -project Ledge.xcodeproj -scheme Ledge -destination 'platform=macOS' -derivedDataPath .build/DerivedData -enableCodeCoverage YES -resultBundlePath .build/LedgeBaseline4.xcresult ONLY_ACTIVE_ARCH=YES` built all test targets and ran 12 tests: 11 passed, 1 failed. The failure is `LedgeUITests-Runner` initialization: “Authentication canceled. System authentication is running.” The nonzero-test gate correctly rejected this failed result. UI behavior and hardware scenarios remain unqualified. `ONLY_ACTIVE_ARCH=YES` avoids Xcode's arm64 package-module versus x86_64 app compile mismatch for this test action; the default-architecture attempt failed before execution.

## Coverage and diagnostics

`Scripts/check-coverage.sh` now reads `xccov` target/file covered and executable line counts. Each product target must independently meet 80%; `.xctest` bundles alone are excluded. The 100%-plus-0% fixture correctly fails. On the partial Xcode result, product coverage was 34/2,660 lines (1.28%) and the gate failed: AgentIPC 0/77, AutomationStorage 0/208, CaptureFeature 0/368, GitHubIntegration 0/80, HandoffFeature 12/275, Ledge.app 0/1,467, LedgeDomain 22/157, NotificationRouting 0/28. This partial-run coverage is not a passing baseline or a claim that unlisted code was exercised.

The selected-Xcode Release `xcodebuild build` and Debug `xcodebuild analyze ... ONLY_ACTIVE_ARCH=YES` exited 0. The public API scan exited 0. The third-party license scan failed because its recursive grep traverses `Packages/LedgeKit/.build` binary artifacts; no matching first-party source was found by source-only search. That script is outside this Task 0 ownership and needs a source-scoped scan before CI can pass. No signed agent, permissions, display topology, or real UI interaction was qualified here.
