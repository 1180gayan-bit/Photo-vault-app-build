import SwiftUI
import CryptoKit

/// The vault's contents while it is unlocked: albums, items, and access to the encrypted files.
@MainActor
final class VaultStore: ObservableObject {
    enum Status: Equatable {
        case closed
        case open
        case failed(String)
    }

    @Published private(set) var status: Status = .closed
    @Published private(set) var albums: [Album] = []
    @Published private(set) var items: [VaultItem] = []

    let files = VaultFiles()
    private var key: SymmetricKey?
    private let thumbnailCache = NSCache<NSUUID, UIImage>()

    init() {
        // Remove any decrypted copies left behind if the app was closed unexpectedly.
        files.clearTemporaryFiles()
    }

    // MARK: Open / close

    func open() {
        do {
            try files.prepareDirectories()
            let key: SymmetricKey
            if let existing = MasterKey.load() {
                key = existing
            } else if files.indexExists {
                // Never replace the key of an existing vault: that would make it unreadable.
                status = .failed(VaultError.missingKey.localizedDescription)
                return
            } else {
                key = try MasterKey.create()
            }
            self.key = key

            if files.indexExists {
                let sealed = try Data(contentsOf: files.indexURL)
                let index = try JSONDecoder().decode(VaultIndex.self, from: VaultCrypto.open(sealed, key: key))
                albums = index.albums
                items = index.items
            } else {
                albums = [Album(name: "My Album")]
                items = []
                try save()
            }
            status = .open
        } catch {
            key = nil
            status = .failed(error.localizedDescription)
        }
    }

    func close() {
        key = nil
        albums = []
        items = []
        thumbnailCache.removeAllObjects()
        files.clearTemporaryFiles()
        status = .closed
    }

    private func save() throws {
        guard let key else { throw VaultError.locked }
        let data = try JSONEncoder().encode(VaultIndex(albums: albums, items: items))
        try VaultCrypto.seal(data, key: key).write(to: files.indexURL, options: [.atomic, .completeFileProtection])
    }

    private func persist() {
        do {
            try save()
        } catch {
            status = .failed("Couldn't save your changes: \(error.localizedDescription)")
        }
    }

    // MARK: Queries

    func album(_ id: UUID) -> Album? {
        albums.first { $0.id == id }
    }

    /// Items in an album, newest first.
    func items(in albumID: UUID) -> [VaultItem] {
        items.filter { $0.albumID == albumID }.sorted { $0.addedAt > $1.addedAt }
    }

    func coverItem(for album: Album) -> VaultItem? {
        if let coverID = album.coverItemID,
           let cover = items.first(where: { $0.id == coverID && $0.albumID == album.id }) {
            return cover
        }
        return items(in: album.id).first
    }

    var photoCount: Int { items.filter { $0.kind == .photo }.count }
    var videoCount: Int { items.filter { $0.kind == .video }.count }

    func bytesUsed() async -> Int64 {
        let files = self.files
        return await Task.detached { files.bytesUsed() }.value
    }

    // MARK: Albums

    @discardableResult
    func createAlbum(named name: String) -> Album {
        let album = Album(name: Self.cleanName(name))
        albums.append(album)
        persist()
        return album
    }

    func renameAlbum(_ id: UUID, to name: String) {
        guard let index = albums.firstIndex(where: { $0.id == id }) else { return }
        albums[index].name = Self.cleanName(name)
        persist()
    }

    /// Deletes the album and everything in it.
    func deleteAlbum(_ id: UUID) {
        let doomed = items.filter { $0.albumID == id }
        doomed.forEach { removeFiles(for: $0.id) }
        items.removeAll { $0.albumID == id }
        albums.removeAll { $0.id == id }
        persist()
    }

    func moveAlbums(fromOffsets source: IndexSet, toOffset destination: Int) {
        albums.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func setCover(_ item: VaultItem) {
        guard let index = albums.firstIndex(where: { $0.id == item.albumID }) else { return }
        albums[index].coverItemID = item.id
        persist()
    }

    private static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Album" : trimmed
    }

    // MARK: Items

    func move(_ ids: Set<UUID>, to albumID: UUID) {
        for index in items.indices where ids.contains(items[index].id) {
            items[index].albumID = albumID
        }
        for index in albums.indices {
            if let cover = albums[index].coverItemID, ids.contains(cover), albums[index].id != albumID {
                albums[index].coverItemID = nil
            }
        }
        persist()
    }

    func delete(_ ids: Set<UUID>) {
        ids.forEach { removeFiles(for: $0) }
        items.removeAll { ids.contains($0.id) }
        for index in albums.indices {
            if let cover = albums[index].coverItemID, ids.contains(cover) {
                albums[index].coverItemID = nil
            }
        }
        persist()
    }

    private func removeFiles(for id: UUID) {
        files.removeFiles(for: id)
        thumbnailCache.removeObject(forKey: id as NSUUID)
    }

    // MARK: Import

    func importPhoto(data: Data, fileExtension: String, into albumID: UUID) async throws {
        guard let key else { throw VaultError.locked }
        let id = UUID()
        let files = self.files
        try await Task.detached(priority: .userInitiated) {
            try VaultCrypto.encrypt(data, toFileAt: files.mediaURL(for: id), key: key)
            if let thumbnail = Thumbnailer.photoThumbnail(from: data) {
                try VaultCrypto.encrypt(thumbnail, toFileAt: files.thumbnailURL(for: id), key: key)
            }
        }.value
        try add(VaultItem(id: id, albumID: albumID, kind: .photo, addedAt: Date(), duration: nil, fileExtension: fileExtension))
    }

    /// Encrypts a video file into the vault, then deletes the unencrypted source file.
    func importVideo(at sourceURL: URL, into albumID: UUID) async throws {
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        guard let key else { throw VaultError.locked }
        let id = UUID()
        let files = self.files
        let duration = try await Task.detached(priority: .userInitiated) { () async throws -> Double? in
            let duration = await Thumbnailer.videoDuration(for: sourceURL)
            if let thumbnail = await Thumbnailer.videoThumbnail(for: sourceURL) {
                try VaultCrypto.encrypt(thumbnail, toFileAt: files.thumbnailURL(for: id), key: key)
            }
            try VaultCrypto.encryptFile(at: sourceURL, toFileAt: files.mediaURL(for: id), key: key)
            return duration
        }.value
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension.lowercased()
        try add(VaultItem(id: id, albumID: albumID, kind: .video, addedAt: Date(), duration: duration, fileExtension: ext))
    }

    private func add(_ item: VaultItem) throws {
        // If the vault locked while we were encrypting, throw the new files away.
        guard key != nil, albums.contains(where: { $0.id == item.albumID }) else {
            files.removeFiles(for: item.id)
            throw VaultError.locked
        }
        items.append(item)
        try save()
    }

    // MARK: Reading

    func thumbnail(for item: VaultItem) async -> UIImage? {
        if let cached = thumbnailCache.object(forKey: item.id as NSUUID) { return cached }
        guard let key else { return nil }
        let url = files.thumbnailURL(for: item.id)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? VaultCrypto.decrypt(fileAt: url, key: key) else { return nil }
            return UIImage(data: data)
        }.value
        if let image { thumbnailCache.setObject(image, forKey: item.id as NSUUID) }
        return image
    }

    /// The photo decoded at a size suited to the screen (still sharp when zoomed in).
    func displayImage(for item: VaultItem, maxPixelSize: Int = 3000) async throws -> UIImage {
        guard let key else { throw VaultError.locked }
        let url = files.mediaURL(for: item.id)
        return try await Task.detached(priority: .userInitiated) { () throws -> UIImage in
            let data = try VaultCrypto.decrypt(fileAt: url, key: key)
            guard let image = Thumbnailer.downsampledImage(from: data, maxPixelSize: maxPixelSize) ?? UIImage(data: data) else {
                throw VaultCryptoError.badFormat
            }
            return image
        }.value
    }

    /// Decrypts an item to a temporary file (for video playback, sharing or saving to Photos).
    /// Temporary files are deleted when the viewer closes and whenever the vault locks.
    func temporaryFile(for item: VaultItem) async throws -> URL {
        guard let key else { throw VaultError.locked }
        let destination = files.tempDirectory
            .appendingPathComponent(item.id.uuidString)
            .appendingPathExtension(item.fileExtension)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        let source = files.mediaURL(for: item.id)
        let partial = files.newTemporaryURL(fileExtension: "part")
        try await Task.detached(priority: .userInitiated) {
            try VaultCrypto.decrypt(fileAt: source, toFileAt: partial, key: key)
            try FileManager.default.moveItem(at: partial, to: destination)
        }.value
        return destination
    }

    func clearTemporaryFiles() {
        files.clearTemporaryFiles()
    }
}
