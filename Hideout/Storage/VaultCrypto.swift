import Foundation
import CryptoKit

enum VaultCryptoError: LocalizedError {
    case badFormat
    case truncated

    var errorDescription: String? {
        switch self {
        case .badFormat: return "This file isn't a vault file."
        case .truncated: return "This vault file is incomplete or damaged."
        }
    }
}

/// Encrypts files with AES-256-GCM.
///
/// Large files (videos) are split into 1 MB chunks so they never have to fit in memory.
/// File layout: "HDV1", then for each chunk: [1 byte final flag][4 byte length][sealed box].
/// Each chunk is authenticated together with its position and final flag, so chunks
/// can't be reordered, swapped between files undetected, or cut off.
enum VaultCrypto {
    static let chunkSize = 1 << 20
    private static let magic = Data("HDV1".utf8)

    // MARK: Small blobs (the vault index)

    static func seal(_ data: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else {
            throw VaultCryptoError.badFormat
        }
        return combined
    }

    static func open(_ data: Data, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
    }

    // MARK: Files

    static func encrypt(_ data: Data, toFileAt url: URL, key: SymmetricKey) throws {
        var offset = 0
        try encryptStream(to: url, key: key) {
            let end = min(offset + chunkSize, data.count)
            defer { offset = end }
            guard offset < end else { return Data() }
            return data.subdata(in: (data.startIndex + offset)..<(data.startIndex + end))
        }
    }

    static func encryptFile(at source: URL, toFileAt url: URL, key: SymmetricKey) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        try encryptStream(to: url, key: key) {
            try input.read(upToCount: chunkSize) ?? Data()
        }
    }

    static func decrypt(fileAt url: URL, key: SymmetricKey) throws -> Data {
        var output = Data()
        try decryptChunks(fileAt: url, key: key) { output.append($0) }
        return output
    }

    static func decrypt(fileAt url: URL, toFileAt destination: URL, key: SymmetricKey) throws {
        let output = try createProtectedFile(at: destination)
        defer { try? output.close() }
        try decryptChunks(fileAt: url, key: key) { try output.write(contentsOf: $0) }
    }

    // MARK: Internals

    private static func encryptStream(to url: URL, key: SymmetricKey, nextChunk: () throws -> Data) throws {
        let output = try createProtectedFile(at: url)
        defer { try? output.close() }
        try output.write(contentsOf: magic)

        var index: UInt64 = 0
        var current = try nextChunk()
        while true {
            let next = try nextChunk()
            let flag: UInt8 = next.isEmpty ? 1 : 0
            let box = try AES.GCM.seal(current, using: key, authenticating: associatedData(index: index, flag: flag))
            guard let combined = box.combined else { throw VaultCryptoError.badFormat }

            var header = Data([flag])
            header.append(UInt32(combined.count).bigEndianBytes)
            try output.write(contentsOf: header)
            try output.write(contentsOf: combined)

            if flag == 1 { break }
            current = next
            index += 1
        }
    }

    private static func decryptChunks(fileAt url: URL, key: SymmetricKey, handler: (Data) throws -> Void) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }

        guard let header = try input.read(upToCount: magic.count), header == magic else {
            throw VaultCryptoError.badFormat
        }

        var index: UInt64 = 0
        while true {
            guard let chunkHeader = try input.read(upToCount: 5), chunkHeader.count == 5 else {
                throw VaultCryptoError.truncated
            }
            let bytes = [UInt8](chunkHeader)
            let flag = bytes[0]
            let length = bytes[1...4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard flag <= 1, Int(length) <= chunkSize + 64 else { throw VaultCryptoError.badFormat }
            guard let combined = try input.read(upToCount: Int(length)), combined.count == Int(length) else {
                throw VaultCryptoError.truncated
            }
            let box = try AES.GCM.SealedBox(combined: combined)
            let plain = try AES.GCM.open(box, using: key, authenticating: associatedData(index: index, flag: flag))
            try handler(plain)
            if flag == 1 { break }
            index += 1
        }
    }

    private static func associatedData(index: UInt64, flag: UInt8) -> Data {
        var data = magic
        data.append(index.bigEndianBytes)
        data.append(flag)
        return data
    }

    /// Creates an empty file that iOS keeps encrypted while the phone is locked.
    static func createProtectedFile(at url: URL) throws -> FileHandle {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
        guard manager.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.complete]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try FileHandle(forWritingTo: url)
    }
}

extension FixedWidthInteger {
    var bigEndianBytes: Data {
        withUnsafeBytes(of: bigEndian) { Data($0) }
    }
}
