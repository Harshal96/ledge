import CryptoKit
import Foundation
import LedgeDomain
import Security

public enum PayloadVaultError: Error, Equatable, Sendable {
    case authenticationFailed, invalidEnvelope, missingPayload, invalidKeychainItem, fileSystem
}

enum PayloadEnvelope {
    static let chunkSize = 1_048_576
    private static let magic = Data("LEDGE1".utf8)

    static func seal(_ plaintext: Data, id: UUID, kind: ShelfItemKind, key: SymmetricKey) throws -> Data {
        var header = magic
        header.append(1)
        header.append(contentsOf: uuidBytes(id))
        header.append(kindByte(kind))
        header.appendUInt64(UInt64(plaintext.count))
        header.appendUInt32(UInt32(chunkSize))
        var prefix = Data(count: 8)
        _ = prefix.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) }
        header.append(prefix)
        var output = header
        try appendRecord(index: UInt32.max, plaintext: Data(), header: header, prefix: prefix, output: &output, key: key)
        var index: UInt32 = 0
        var offset = 0
        while offset < plaintext.count {
            let count = min(chunkSize, plaintext.count - offset)
            try appendRecord(index: index, plaintext: plaintext.subdata(in: offset..<(offset + count)), header: header, prefix: prefix, output: &output, key: key)
            offset += count; index &+= 1
        }
        return output
    }

    static func open(_ envelope: Data, id: UUID, kind: ShelfItemKind, key: SymmetricKey) throws -> Data {
        var cursor = 0
        guard envelope.count >= 43, readData(envelope, &cursor, 6) == magic, readByte(envelope, &cursor) == 1,
              let storedID = readData(envelope, &cursor, 16), let storedKind = readByte(envelope, &cursor),
              let declared = readUInt64(envelope, &cursor), declared <= UInt64(Int.max),
              readUInt32(envelope, &cursor) == UInt32(chunkSize), let prefix = optionalData(envelope, &cursor, 8)
        else { throw PayloadVaultError.invalidEnvelope }
        guard storedID == Data(uuidBytes(id)), storedKind == kindByte(kind) else { throw PayloadVaultError.authenticationFailed }
        let header = envelope.subdata(in: 0..<cursor)
        try openRecord(index: UInt32.max, expectedLength: 0, envelope: envelope, cursor: &cursor, header: header, prefix: prefix, key: key).requireEmpty()
        var result = Data(); result.reserveCapacity(Int(declared))
        var index: UInt32 = 0
        while result.count < Int(declared) {
            let remaining = Int(declared) - result.count
            let expected = min(chunkSize, remaining)
            let part = try openRecord(index: index, expectedLength: expected, envelope: envelope, cursor: &cursor, header: header, prefix: prefix, key: key)
            guard part.count == expected else { throw PayloadVaultError.invalidEnvelope }
            result.append(part); index &+= 1
        }
        guard cursor == envelope.count else { throw PayloadVaultError.invalidEnvelope }
        return result
    }

    private static func appendRecord(index: UInt32, plaintext: Data, header: Data, prefix: Data, output: inout Data, key: SymmetricKey) throws {
        let nonce = try AES.GCM.Nonce(data: prefix + index.bigEndianData)
        let aad = header + index.bigEndianData + UInt32(plaintext.count).bigEndianData
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
        guard let combined = sealed.combined else { throw PayloadVaultError.authenticationFailed }
        output.appendUInt32(index); output.appendUInt32(UInt32(plaintext.count)); output.appendUInt32(UInt32(combined.count)); output.append(combined)
    }

    private static func openRecord(index: UInt32, expectedLength: Int, envelope: Data, cursor: inout Int, header: Data, prefix: Data, key: SymmetricKey) throws -> Data {
        guard readUInt32(envelope, &cursor) == index, readUInt32(envelope, &cursor) == UInt32(expectedLength),
              let sealedLength = readUInt32(envelope, &cursor), sealedLength == UInt32(expectedLength + 28),
              let combined = optionalData(envelope, &cursor, Int(sealedLength)), combined.prefix(8) == prefix, combined.dropFirst(8).prefix(4) == index.bigEndianData
        else { throw PayloadVaultError.invalidEnvelope }
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key, authenticating: header + index.bigEndianData + UInt32(expectedLength).bigEndianData)
        } catch { throw PayloadVaultError.authenticationFailed }
    }

    private static func uuidBytes(_ id: UUID) -> [UInt8] { withUnsafeBytes(of: id.uuid) { Array($0) } }
    private static func kindByte(_ kind: ShelfItemKind) -> UInt8 { UInt8(ShelfItemKind.allCases.firstIndex(of: kind)!) }
    private static func readByte(_ data: Data, _ cursor: inout Int) -> UInt8? { guard cursor < data.count else { return nil }; defer { cursor += 1 }; return data[cursor] }
    private static func optionalData(_ data: Data, _ cursor: inout Int, _ count: Int) -> Data? { guard count >= 0, cursor + count <= data.count else { return nil }; defer { cursor += count }; return data.subdata(in: cursor..<(cursor + count)) }
    private static func readData(_ data: Data, _ cursor: inout Int, _ count: Int) -> Data? { optionalData(data, &cursor, count) }
    private static func readUInt32(_ data: Data, _ cursor: inout Int) -> UInt32? { optionalData(data, &cursor, 4).map { $0.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian } } }
    private static func readUInt64(_ data: Data, _ cursor: inout Int) -> UInt64? { optionalData(data, &cursor, 8).map { $0.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian } } }
}

private extension Data { mutating func appendUInt32(_ value: UInt32) { append(value.bigEndianData) }; mutating func appendUInt64(_ value: UInt64) { append(value.bigEndianData) } }
private extension FixedWidthInteger { var bigEndianData: Data { withUnsafeBytes(of: bigEndian) { Data($0) } } }
private extension Data { func requireEmpty() throws { guard isEmpty else { throw PayloadVaultError.invalidEnvelope } } }
