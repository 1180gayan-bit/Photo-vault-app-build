import Foundation
import CommonCrypto

/// Stores the app passcode as a salted PBKDF2 hash in the Keychain.
/// The passcode itself is never saved anywhere.
enum Passcode {
    static let length = 6

    private static let account = "passcode-hash"
    private static let saltLength = 16
    private static let hashLength = 32
    private static let rounds: UInt32 = 120_000

    static var isSet: Bool {
        Keychain.data(for: account) != nil
    }

    static func set(_ code: String) throws {
        let salt = Keychain.randomBytes(saltLength)
        let hash = derive(code, salt: salt)
        try Keychain.set(salt + hash, for: account)
    }

    static func verify(_ code: String) -> Bool {
        guard let stored = Keychain.data(for: account),
              stored.count == saltLength + hashLength else { return false }
        let salt = Data(stored.prefix(saltLength))
        let expected = Data(stored.suffix(hashLength))
        return constantTimeEqual(derive(code, salt: salt), expected)
    }

    private static func derive(_ code: String, salt: Data) -> Data {
        var derived = [UInt8](repeating: 0, count: hashLength)
        let saltBytes = [UInt8](salt)
        let passwordLength = code.utf8.count
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            code, passwordLength,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            rounds,
            &derived, derived.count
        )
        precondition(status == kCCSuccess, "Passcode hashing failed")
        return Data(derived)
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }
}
