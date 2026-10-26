import Foundation
import LedgeDomain

public enum HandoffExpiry: Sendable, Equatable, CaseIterable {
    case oneHour, oneDay, sevenDays, keep
    public func date(from now: Date) -> Date? {
        switch self { case .oneHour: now.addingTimeInterval(3_600); case .oneDay: now.addingTimeInterval(86_400); case .sevenDays: now.addingTimeInterval(7 * 86_400); case .keep: nil }
    }
}

public enum IncomingPayload: Sendable, Equatable {
    case text(String)
    case url(URL)
    case file(FileDescriptorSource)

    public var isAccepted: Bool { true }
    public var shelfKind: ShelfItemKind { switch self { case .text: .trayText; case .url: .trayURL; case .file: .trayFile } }
    public var content: ShelfContent {
        switch self { case let .text(value): .text(value); case let .url(value): .url(value); case let .file(file): .binary(file.descriptor) }
    }
}

public enum HandoffError: Error, Sendable, Equatable {
    case directoryUnsupported, symbolicLinkUnsupported, specialFileUnsupported, unavailableSecurityScope
    case unsupportedInput, invalidURL, tooManyItems, itemTooLarge, vaultCapacityExceeded, insufficientDiskSpace
    case invalidDisplayName, itemNotFound, corruptedExport, overwriteNotConfirmed
}
