import CoreGraphics

public struct ScreenDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let safeAreaInsets: EdgeInsets
    public let auxiliaryTopLeftArea: CGRect?
    public let auxiliaryTopRightArea: CGRect?
    public let isBuiltIn: Bool

    public init(id: String, frame: CGRect, visibleFrame: CGRect, safeAreaInsets: EdgeInsets, auxiliaryTopLeftArea: CGRect?, auxiliaryTopRightArea: CGRect?, isBuiltIn: Bool) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaInsets = safeAreaInsets
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.isBuiltIn = isBuiltIn
    }
}

public struct EdgeInsets: Sendable, Equatable {
    public let top: CGFloat
    public let left: CGFloat
    public let bottom: CGFloat
    public let right: CGFloat

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = EdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
}
