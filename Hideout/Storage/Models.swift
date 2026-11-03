import Foundation

struct Album: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// The item shown on the album's tile. When nil, the newest item is used.
    var coverItemID: UUID?
    var createdAt = Date()
}

struct VaultItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case photo
        case video
    }

    let id: UUID
    var albumID: UUID
    let kind: Kind
    let addedAt: Date
    /// Video length in seconds.
    var duration: Double?
    /// Original file type, e.g. "heic", "jpg" or "mov". Used when exporting.
    let fileExtension: String
}

/// Everything the vault knows about its albums and items. Saved encrypted as one file.
struct VaultIndex: Codable {
    var version = 1
    var albums: [Album]
    var items: [VaultItem]
}

enum VaultError: LocalizedError {
    case locked
    case missingKey
    case importFailed

    var errorDescription: String? {
        switch self {
        case .locked:
            return "The vault is locked."
        case .missingKey:
            return "The vault's encryption key couldn't be found on this iPhone."
        case .importFailed:
            return "This item couldn't be imported."
        }
    }
}
