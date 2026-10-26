import AppKit
import Foundation
import LedgeDomain

public enum ShareMode: Sendable, Equatable { case general, airDrop }

public struct ShelfFileReference: Sendable, Equatable {
    public let itemID: UUID
    public let descriptor: BinaryDescriptor
    public init(itemID: UUID, descriptor: BinaryDescriptor) { self.itemID = itemID; self.descriptor = descriptor }
}

public enum SharePayload: Sendable, Equatable {
    case text(String)
    case url(URL)
    case file(ShelfFileReference)
}

public enum ShareItem: Sendable, Equatable { case text(String), url(URL), file(URL) }
public enum SharingResult: Sendable, Equatable { case completed, cancelled, failed(String) }
public enum ShareError: Error, Sendable, Equatable { case unavailable, cancelled, failed(String), presentationSafeRevealRequired }

/// The only file boundary used by sharing. Implementations must create a new bounded,
/// decrypted export and remove it when asked; they must never hand out the vault path.
public protocol TemporaryShareExporting: Sendable {
    func exportTemporary(itemID: UUID, suggestedName: String) async throws -> URL
    func removeTemporary(_ url: URL) async
}

/// Implementations must not return `.completed` until the system surface has finished consuming
/// its inputs. This keeps file exports alive for the complete share transaction.
public protocol SharingClient: Sendable {
    func isAvailable(for mode: ShareMode) async -> Bool
    func share(_ items: [ShareItem], mode: ShareMode) async -> SharingResult
}

public enum ExternalInteractionKind: Sendable, Equatable { case sharePicker }
public protocol ExternalInteractionLeasing: Sendable {
    func acquire(kind: ExternalInteractionKind) async -> UUID
    func release(_ token: UUID) async
}

public actor ShareService {
    private let exporter: any TemporaryShareExporting
    private let sharingClient: any SharingClient
    private let interactionLease: (any ExternalInteractionLeasing)?

    public init(exporter: any TemporaryShareExporting, sharingClient: any SharingClient, interactionLease: (any ExternalInteractionLeasing)? = nil) {
        self.exporter = exporter; self.sharingClient = sharingClient; self.interactionLease = interactionLease
    }

    public func share(_ payload: SharePayload, mode: ShareMode = .general, presentationSafeRevealed: Bool = true) async throws {
        guard presentationSafeRevealed else { throw ShareError.presentationSafeRevealRequired }
        guard await sharingClient.isAvailable(for: mode) else { throw ShareError.unavailable }
        let lease = await interactionLease?.acquire(kind: .sharePicker)
        var temporaryURL: URL?
        let result: SharingResult
        do {
            let items: [ShareItem]
            switch payload {
            case let .text(text): items = [.text(text)]
            case let .url(url): items = [.url(url)]
            case let .file(file):
                let exported = try await exporter.exportTemporary(itemID: file.itemID, suggestedName: file.descriptor.displayName)
                temporaryURL = exported
                items = [.file(exported)]
            }
            result = await sharingClient.share(items, mode: mode)
        } catch {
            if let temporaryURL { await exporter.removeTemporary(temporaryURL) }
            if let lease { await interactionLease?.release(lease) }
            throw error
        }
        if let temporaryURL { await exporter.removeTemporary(temporaryURL) }
        if let lease { await interactionLease?.release(lease) }
        try Self.finish(result)
    }

    private static func finish(_ result: SharingResult) throws {
        switch result {
        case .completed: return
        case .cancelled: throw ShareError.cancelled
        case let .failed(message): throw ShareError.failed(message)
        }
    }
}

/// Public-AppKit adapter. App composition supplies an anchor and retains the presenter;
/// the service never uses private sharing APIs or performs network work itself.
@MainActor public final class AppKitSharingClient: NSObject, SharingClient, @unchecked Sendable {
    private var activeDelegates: [UUID: AppKitShareDelegate] = [:]
    public override init() {}
    public func isAvailable(for mode: ShareMode) async -> Bool {
        switch mode {
        case .airDrop: return NSSharingService(named: .sendViaAirDrop) != nil
        // General sharing must be driven through an anchored picker coordinator below.
        case .general: return false
        }
    }

    /// Presents an anchored `NSSharingServicePicker` using only public AppKit APIs.
    /// Completion is deliberately owned by the caller's picker delegate/presentation coordinator.
    public func presentPicker(items: [ShareItem], relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge = .maxY) {
        let picker = NSSharingServicePicker(items: items.compactMap(Self.appKitItem))
        picker.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
    }

    public func share(_ items: [ShareItem], mode: ShareMode) async -> SharingResult {
        guard mode == .airDrop, let service = NSSharingService(named: .sendViaAirDrop) else { return .failed("Use an anchored NSSharingServicePicker coordinator for general sharing") }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            let delegate = AppKitShareDelegate { [weak self] result in
                self?.activeDelegates.removeValue(forKey: id)
                continuation.resume(returning: result)
            }
            activeDelegates[id] = delegate // `NSSharingService.delegate` is not an ownership boundary.
            service.delegate = delegate
            service.perform(withItems: items.compactMap(Self.appKitItem))
            Task { @MainActor [weak delegate] in
                try? await Task.sleep(for: .seconds(60))
                delegate?.finish(.cancelled)
            }
        }
    }

    private static func appKitItem(_ item: ShareItem) -> Any? {
        switch item { case let .text(value): value; case let .url(value): value; case let .file(value): value }
    }
}

@MainActor private final class AppKitShareDelegate: NSObject, NSSharingServiceDelegate {
    private var completion: ((SharingResult) -> Void)?
    init(completion: @escaping (SharingResult) -> Void) { self.completion = completion }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish(.completed) }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { finish(.failed(error.localizedDescription)) }
    func finish(_ result: SharingResult) { guard let completion else { return }; self.completion = nil; completion(result) }
}
