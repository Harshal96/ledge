import Foundation
import Testing
@testable import ShellFeature

@Test func notchDwellExitAndPeekUseOneClockWithoutStealingFocus() {
    var controller = NotchPresentationController()
    controller.send(.pointerEntered, now: 0)
    controller.send(.advance, now: 0.199)
    #expect(controller.snapshot.presentation == .hidden)
    controller.send(.advance, now: 0.2)
    #expect(controller.snapshot.presentation == .expanded(nil))
    #expect(!controller.snapshot.requestsKeyboard)
    controller.send(.pointerExited, now: 1)
    controller.send(.advance, now: 1.349)
    #expect(controller.snapshot.presentation == .expanded(nil))
    controller.send(.advance, now: 1.35)
    #expect(controller.snapshot.presentation == .hidden)
    controller.send(.notify("Build completed"), now: 2)
    #expect(controller.snapshot.presentation == .peek)
    controller.send(.advance, now: 7)
    #expect(controller.snapshot.presentation == .hidden)
}

@Test func notchExplicitOpenSurvivesSuppressionAndInteractionLease() {
    var controller = NotchPresentationController()
    controller.send(.suppressAutomatic(true), now: 0)
    controller.send(.pointerEntered, now: 0)
    controller.send(.advance, now: 1)
    #expect(controller.snapshot.presentation == .hidden)
    controller.send(.open("instance"), now: 1)
    #expect(controller.snapshot.requestsKeyboard)
    controller.send(.interaction(true), now: 2)
    controller.send(.dismiss, now: 2)
    #expect(controller.snapshot.presentation == .expanded("instance"))
    controller.send(.interaction(false), now: 3)
    #expect(controller.snapshot.presentation == .hidden)
}
