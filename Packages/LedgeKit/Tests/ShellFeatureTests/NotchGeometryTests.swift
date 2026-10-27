import Foundation
import Testing
@testable import ShellFeature

@Test func notchContentStaysBelowHousingButHoverIncludesTheHousing() {
    let screen = ScreenDescriptor(id: "display:1", frame: CGRect(x: -1512, y: 0, width: 1512, height: 982), visibleFrame: CGRect(x: -1512, y: 0, width: 1512, height: 945), safeAreaInsets: .init(top: 37, left: 0, bottom: 0, right: 0), auxiliaryTopLeftArea: CGRect(x: -1512, y: 945, width: 632, height: 37), auxiliaryTopRightArea: CGRect(x: -632, y: 945, width: 632, height: 37), isBuiltIn: true)
    let layout = NotchGeometryResolver().resolve(screen: screen, expanded: true)
    #expect(layout.frame.maxY == 945)
    #expect(layout.frame.width == 560)
    #expect(layout.trigger.contains(CGPoint(x: -756, y: 970)))
    #expect(layout.trigger.contains(CGPoint(x: -756, y: 942)))
    #expect(layout.trigger.maxY == 982)
    #expect(layout.trigger.minX >= -880)
    #expect(layout.trigger.maxX <= -632)
}

@Test func notchlessHoverUsesTheActualScreenTopInsteadOfBelowTheMenuBar() {
    let screen = ScreenDescriptor(id: "external", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056), safeAreaInsets: .zero, auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: false)
    let layout = NotchGeometryResolver().resolve(screen: screen, expanded: true)
    #expect(layout.trigger.contains(CGPoint(x: 960, y: 1079)))
    #expect(layout.frame.maxY == 1056)
    #expect(!layout.trigger.contains(CGPoint(x: 20, y: 1079)))
}
