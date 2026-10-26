import CoreGraphics

public struct ShelfPlacement: Sendable, Equatable {
    public let frame: CGRect
    public let topInset: CGFloat

    public init(frame: CGRect, topInset: CGFloat) {
        self.frame = frame
        self.topInset = topInset
    }
}

public struct ShelfGeometryResolver: Sendable {
    public init() {}

    public func placement(screen: ScreenDescriptor, contentSize: CGSize) -> ShelfPlacement {
        let topInset = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)
        let desiredWidth = min(max(0, contentSize.width), screen.visibleFrame.width)
        let desiredHeight = min(max(0, contentSize.height), screen.visibleFrame.height)
        let desired = CGRect(
            x: screen.frame.midX - desiredWidth / 2,
            y: screen.frame.maxY - topInset - desiredHeight,
            width: desiredWidth,
            height: desiredHeight
        )
        return ShelfPlacement(frame: clamp(desired, to: screen.visibleFrame), topInset: topInset)
    }

    private func clamp(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        let width = min(frame.width, bounds.width)
        let height = min(frame.height, bounds.height)
        return CGRect(
            x: min(max(frame.minX, bounds.minX), bounds.maxX - width),
            y: min(max(frame.minY, bounds.minY), bounds.maxY - height),
            width: width,
            height: height
        )
    }
}
