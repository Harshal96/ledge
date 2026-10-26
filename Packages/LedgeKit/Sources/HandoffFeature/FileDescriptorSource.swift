import Darwin
import Foundation
import LedgeDomain

public struct FileDescriptorSource: @unchecked Sendable, Equatable {
    public let url: URL
    public let descriptor: BinaryDescriptor
    private let fileDescriptor: Int32

    public init(url: URL, maximumBytes: Int64 = 500 * 1_024 * 1_024) throws {
        var linkStatus = stat()
        guard lstat(url.path, &linkStatus) == 0 else { throw HandoffError.unsupportedInput }
        if (linkStatus.st_mode & S_IFMT) == S_IFLNK { throw HandoffError.symbolicLinkUnsupported }
        if (linkStatus.st_mode & S_IFMT) == S_IFDIR { throw HandoffError.directoryUnsupported }
        guard (linkStatus.st_mode & S_IFMT) == S_IFREG else { throw HandoffError.specialFileUnsupported }
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw HandoffError.unsupportedInput }
        var heldStatus = stat()
        guard fstat(fd, &heldStatus) == 0, (heldStatus.st_mode & S_IFMT) == S_IFREG else { Darwin.close(fd); throw HandoffError.specialFileUnsupported }
        guard heldStatus.st_size >= 0, heldStatus.st_size <= maximumBytes else { Darwin.close(fd); throw HandoffError.itemTooLarge }
        let name = Self.sanitizedDisplayName(url.lastPathComponent)
        guard !name.isEmpty else { Darwin.close(fd); throw HandoffError.invalidDisplayName }
        self.url = url
        self.fileDescriptor = fd
        self.descriptor = .init(displayName: name, byteCount: Int(heldStatus.st_size), uniformTypeIdentifier: nil)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.url == rhs.url && lhs.descriptor == rhs.descriptor }
    public func readData() throws -> Data {
        guard lseek(fileDescriptor, 0, SEEK_SET) >= 0 else { throw HandoffError.unsupportedInput }
        var result = Data(); var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true { let amount = Darwin.read(fileDescriptor, &buffer, buffer.count); if amount < 0 { throw HandoffError.unsupportedInput }; if amount == 0 { break }; result.append(contentsOf: buffer.prefix(Int(amount))) }
        guard result.count == descriptor.byteCount else { throw HandoffError.unsupportedInput }; return result
    }
    public func close() { Darwin.close(fileDescriptor) }
    public static func sanitizedDisplayName(_ value: String) -> String {
        let leaf = value.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
        return leaf.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }.map(String.init).joined().prefix(255).description
    }
}
