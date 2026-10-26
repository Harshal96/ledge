import AppKit
import CoreGraphics
import Foundation
import ImageIO
import LedgeDomain
import ScreenCaptureKit
import ShellFeature
import UniformTypeIdentifiers

public enum ScreenCapturePermission: Sendable, Equatable { case authorized, denied, notDetermined }

public protocol ScreenCapturePermissionChecking: Sendable {
    func authorization() async -> ScreenCapturePermission
    func requestAccess() async -> ScreenCapturePermission
}

/// Public CoreGraphics permission adapter. `requestAccess` is only called by a direct screenshot action.
public struct CGScreenCapturePermission: ScreenCapturePermissionChecking {
    public init() {}
    public func authorization() async -> ScreenCapturePermission { CGPreflightScreenCaptureAccess() ? .authorized : .notDetermined }
    public func requestAccess() async -> ScreenCapturePermission { CGRequestScreenCaptureAccess() ? .authorized : .denied }
}

public struct ScreenshotFrame: @unchecked Sendable {
    public let image: CGImage
    public init(image: CGImage) { self.image = image }

    public static func fixture(width: Int, height: Int) -> ScreenshotFrame {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ScreenshotFrame(image: context.makeImage()!)
    }
}

public protocol ScreenshotFrameCapturing: Sendable {
    func capture(display: ScreenshotDisplay, excludingBundleIdentifier: String?) async throws -> ScreenshotFrame
}

/// Public ScreenCaptureKit adapter. It captures a display frame with Ledge excluded; cropping and encoding stay in `ScreenshotService`.
@available(macOS 14.0, *)
public struct ScreenCaptureKitScreenshotBackend: ScreenshotFrameCapturing {
    public init() {}
    public func capture(display: ScreenshotDisplay, excludingBundleIdentifier: String?) async throws -> ScreenshotFrame {
        guard let systemDisplayID = display.systemDisplayID else { throw ScreenshotError.displayUnavailable }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let target = content.displays.first(where: { $0.displayID == systemDisplayID }) else { throw ScreenshotError.displayUnavailable }
        let applications = excludingBundleIdentifier.flatMap { identifier in content.applications.filter { $0.bundleIdentifier == identifier } } ?? []
        let filter = SCContentFilter(display: target, excludingApplications: applications, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.frame.width * display.backingScale)
        configuration.height = Int(display.frame.height * display.backingScale)
        return ScreenshotFrame(image: try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration))
    }
}

public enum ScreenshotTarget: Sendable, Equatable { case region(CGRect) }
public enum ScreenshotError: Error, Sendable, Equatable { case permissionDenied, canceled, invalidRegion, displayUnavailable, captureFailed, encodingFailed }

@MainActor
public final class ScreenshotService {
    private let permission: any ScreenCapturePermissionChecking
    private let backend: any ScreenshotFrameCapturing
    private let repository: any ShelfRepository
    private let source: (any SourceContextProviding)?
    private let sourcePolicy: CaptureSourcePolicy
    private weak var panel: (any ShellPanelControlling)?
    private let displays: [ScreenshotDisplay]
    private let excludedBundleIdentifier: String?

    public init(permission: any ScreenCapturePermissionChecking = CGScreenCapturePermission(), backend: any ScreenshotFrameCapturing, repository: any ShelfRepository, source: (any SourceContextProviding)? = nil, sourcePolicy: CaptureSourcePolicy = .attachApplication, panel: (any ShellPanelControlling)? = nil, displays: [ScreenshotDisplay], excludedBundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.permission = permission; self.backend = backend; self.repository = repository; self.source = source; self.sourcePolicy = sourcePolicy; self.panel = panel; self.displays = displays; self.excludedBundleIdentifier = excludedBundleIdentifier
    }

    public func capture(_ target: ScreenshotTarget, now: Date = .now) async throws -> ShelfItem {
        let authorization = await permission.authorization()
        let granted: ScreenCapturePermission
        switch authorization { case .authorized: granted = .authorized; case .denied: throw ScreenshotError.permissionDenied; case .notDetermined: granted = await permission.requestAccess() }
        guard granted == .authorized else { throw ScreenshotError.permissionDenied }
        let region: CGRect
        switch target { case let .region(value): region = value }
        guard let display = displays.first(where: { $0.frame.contains(region) }), region.width > 0, region.height > 0 else { throw ScreenshotError.invalidRegion }

        // Capture the foreground source before hiding our shell, and only when the user opted in.
        let frozenSource = sourcePolicy == .attachApplication ? await source?.snapshot(at: now) : nil
        panel?.dismiss(reason: .actionCompleted)
        defer { panel?.reveal(.quickCapture, reason: .userAction, screenID: display.id) }

        let frame: ScreenshotFrame
        do { frame = try await backend.capture(display: display, excludingBundleIdentifier: excludedBundleIdentifier) }
        catch { throw ScreenshotError.captureFailed }
        let png = try Self.losslessPNG(from: frame.image, region: region, display: display)
        let descriptor = BinaryDescriptor(displayName: "Screenshot.png", byteCount: png.count, uniformTypeIdentifier: UTType.png.identifier)
        let draft = ShelfItemDraft(kind: .screenshot, content: .binary(descriptor), source: frozenSource, createdAt: now, expiresAt: now.addingTimeInterval(30 * 86_400))
        return try await repository.insertBinary(draft, bytes: png)
    }

    private static func losslessPNG(from image: CGImage, region: CGRect, display: ScreenshotDisplay) throws -> Data {
        let scale = display.backingScale
        let local = CGRect(x: (region.minX - display.frame.minX) * scale, y: (display.frame.maxY - region.maxY) * scale, width: region.width * scale, height: region.height * scale).integral
        guard local.minX >= 0, local.minY >= 0, local.maxX <= CGFloat(image.width), local.maxY <= CGFloat(image.height), let cropped = image.cropping(to: local) else { throw ScreenshotError.invalidRegion }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw ScreenshotError.encodingFailed }
        CGImageDestinationAddImage(destination, cropped, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScreenshotError.encodingFailed }
        return output as Data
    }
}
