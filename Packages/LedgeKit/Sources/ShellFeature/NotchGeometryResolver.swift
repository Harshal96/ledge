import CoreGraphics

public struct NotchPlacement: Sendable {
    public let frame: CGRect
    public let trigger: CGRect
    public let hasNotch: Bool
}

public struct NotchGeometryResolver: Sendable {
    public init() {}
    public func resolve(screen: ScreenDescriptor, expanded: Bool, height: CGFloat = 420) -> NotchPlacement {
        let top = screen.frame.maxY - max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)
        let left = screen.auxiliaryTopLeftArea?.maxX ?? screen.frame.midX - 100
        let right = screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX + 100
        let hasNotch = screen.safeAreaInsets.top > 0 && right > left && screen.auxiliaryTopLeftArea != nil
        let center = hasNotch ? (left + right) / 2 : screen.frame.midX
        let width = min(expanded ? 560 : max(200, right - left), screen.visibleFrame.width)
        let h = min(expanded ? height : 56, screen.visibleFrame.height)
        let x = min(max(center - width / 2, screen.visibleFrame.minX), screen.visibleFrame.maxX - width)
        return NotchPlacement(frame: CGRect(x: x, y: top - h, width: width, height: h), trigger: CGRect(x: left, y: top - 6, width: max(0, right - left), height: 6), hasNotch: hasNotch)
    }
}
