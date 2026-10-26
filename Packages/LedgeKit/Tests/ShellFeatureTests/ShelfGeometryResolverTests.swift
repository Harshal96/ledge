import CoreGraphics
import Testing
@testable import ShellFeature

@Test("Notched placement stays below the camera safe area")
func notchedPlacement() {
    let screen = ScreenDescriptor(
        id: "built-in",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945),
        safeAreaInsets: .init(top: 37, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 632, height: 37),
        auxiliaryTopRightArea: CGRect(x: 880, y: 945, width: 632, height: 37),
        isBuiltIn: true
    )

    let placement = ShelfGeometryResolver().placement(
        screen: screen,
        contentSize: CGSize(width: 420, height: 88)
    )

    #expect(placement.frame.midX == screen.frame.midX)
    #expect(placement.frame.maxY <= 945)
    #expect(screen.visibleFrame.contains(placement.frame))
}

@Test("Placement clamps an oversized shelf to an external visible frame")
func oversizedPlacementIsClamped() {
    let screen = ScreenDescriptor(
        id: "external",
        frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1040),
        safeAreaInsets: .zero,
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil,
        isBuiltIn: false
    )

    let placement = ShelfGeometryResolver().placement(
        screen: screen,
        contentSize: CGSize(width: 3_000, height: 2_000)
    )

    #expect(screen.visibleFrame.contains(placement.frame))
    #expect(placement.frame.width == screen.visibleFrame.width)
    #expect(placement.frame.height == screen.visibleFrame.height)
}

@Test("Notch expansion follows the camera span, not a hardcoded screen center")
func notchExpansionUsesActualCameraGeometry() {
    let screen = ScreenDescriptor(id: "notch", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945), safeAreaInsets: .init(top: 37, left: 0, bottom: 0, right: 0), auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 600, height: 37), auxiliaryTopRightArea: CGRect(x: 840, y: 945, width: 672, height: 37), isBuiltIn: true)
    let placement = NotchGeometryResolver().resolve(screen: screen, expanded: true)
    #expect(placement.hasNotch)
    #expect(placement.frame.midX == 720)
    #expect(placement.frame.maxY == 945)
    #expect(placement.trigger.width == 240)
    #expect(screen.visibleFrame.contains(placement.frame))
}

@Test("Notchless fallback stays inside a small negative-origin external display")
func notchlessExpansionClampsToExternalScreen() {
    let screen = ScreenDescriptor(id: "external", frame: CGRect(x: -300, y: 0, width: 300, height: 220), visibleFrame: CGRect(x: -300, y: 0, width: 300, height: 200), safeAreaInsets: .zero, auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: false)
    let placement = NotchGeometryResolver().resolve(screen: screen, expanded: true)
    #expect(!placement.hasNotch)
    #expect(screen.visibleFrame.contains(placement.frame))
}
