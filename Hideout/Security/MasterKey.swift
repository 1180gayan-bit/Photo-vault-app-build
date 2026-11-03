import Foundation
import CryptoKit

/// The 256-bit key that encrypts every file in the vault.
/// It is created once, on first unlock, and kept in the Keychain (this device only).
enum MasterKey {
    private static let account = "master-key"

    static func load() -> SymmetricKey? {
        guard let data = Keychain.data(for: account), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    static func create() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try Keychain.set(data, for: account)
        return key
    }
}
