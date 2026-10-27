import Foundation
import Testing
import CoreGraphics
@testable import ShellFeature

@Test func legacyIconPreferenceCannotReviveStatusItemsOrFeatureRoutes() {
    let preferences = ShellPreferences(legacyMenuIconEnabled: true)
    #expect(!preferences.createsStatusItem)
    #expect(preferences.initialDestination == .library)
}

@Test func buildIdentityDescribesTheRunningExecutableAndOfflineHealth() {
    let identity = BuildIdentity(version: "2.0", build: "7", commit: "abc123", executableURL: URL(fileURLWithPath: "/Applications/Ledge.app/Contents/MacOS/Ledge"))
    #expect(identity.executableURL.path == "/Applications/Ledge.app/Contents/MacOS/Ledge")
    #expect(HostAvailability.unavailable("Signing required").canBrowseLibrary)
    #expect(!HostAvailability.unavailable("Signing required").canRunApps)
}

@Test func selectedDisplayFallsBackAndPointerModeOnlyFollowsExplicitInput() {
    func screen(_ id: String, x: CGFloat, notched: Bool) -> ScreenDescriptor {
        .init(id: id, frame: CGRect(x: x, y: 0, width: 1000, height: 800), visibleFrame: CGRect(x: x, y: 0, width: 1000, height: 770), safeAreaInsets: .init(top: notched ? 30 : 0, left: 0, bottom: 0, right: 0), auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: notched)
    }
    let screens = [screen("external", x: 1000, notched: false), screen("builtin", x: 0, notched: true)]
    #expect(NotchDisplaySelection.select(screens, preference: "external", pointer: nil)?.id == "external")
    #expect(NotchDisplaySelection.select(screens, preference: "disconnected", pointer: nil)?.id == "builtin")
    #expect(NotchDisplaySelection.select(screens, preference: "pointer", pointer: CGPoint(x: 1200, y: 300))?.id == "external")
    #expect(NotchDisplaySelection.select(screens, preference: "pointer", pointer: nil)?.id == "builtin")
    #expect(NotchDisplaySelection.select([], preference: nil, pointer: nil) == nil)
}
