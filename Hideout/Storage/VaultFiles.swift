import Foundation

/// Where the vault keeps its files on the iPhone.
///
///     Application Support/Vault/index.hdv     encrypted list of albums and items
///     Application Support/Vault/media/<id>    encrypted originals
///     Application Support/Vault/thumbs/<id>   encrypted thumbnails
///     tmp/HideoutTemp/                        short-lived decrypted copies (video playback,
///                                             sharing, export); wiped on lock and on launch
struct VaultFiles {
    let root: URL
    let tempDirectory: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Vault", isDirectory: true)
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("HideoutTemp", isDirectory: true)
    }

    var indexURL: URL { root.appendingPathComponent("index.hdv") }
    var mediaDirectory: URL { root.appendingPathComponent("media", isDirectory: true) }
    var thumbnailDirectory: URL { root.appendingPathComponent("thumbs", isDirectory: true) }

    var indexExists: Bool {
        FileManager.default.fileExists(atPath: indexURL.path)
    }

    func mediaURL(for id: UUID) -> URL {
        mediaDirectory.appendingPathComponent(id.uuidString + ".hdv")
    }

    func thumbnailURL(for id: UUID) -> URL {
        thumbnailDirectory.appendingPathComponent(id.uuidString + ".hdv")
    }

    func prepareDirectories() throws {
        let manager = FileManager.default
        for directory in [root, mediaDirectory, thumbnailDirectory, tempDirectory] {
            try manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        // Keep the vault out of iCloud and computer backups: nothing leaves this iPhone.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var rootURL = root
        try rootURL.setResourceValues(values)
    }

    func removeFiles(for id: UUID) {
        try? FileManager.default.removeItem(at: mediaURL(for: id))
        try? FileManager.default.removeItem(at: thumbnailURL(for: id))
    }

    func clearTemporaryFiles() {
        let manager = FileManager.default
        try? manager.removeItem(at: tempDirectory)
        try? manager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    func newTemporaryURL(fileExtension: String) -> URL {
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        return tempDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
    }

    /// Total bytes the vault uses on disk.
    func bytesUsed() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}
