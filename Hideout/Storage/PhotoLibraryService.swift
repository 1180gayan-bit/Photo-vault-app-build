import Foundation
import Photos

enum PhotoLibraryError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        "Hideout doesn't have permission to use your Photos library. You can allow it in the Settings app under Hideout > Photos."
    }
}

/// Talks to the iPhone's Photos library: deleting originals after import, and saving items back.
enum PhotoLibraryService {
    /// Deletes the given photos/videos from the Photos library. iOS shows its own
    /// confirmation first. Returns how many were found and deleted.
    static func deleteAssets(localIdentifiers: [String]) async throws -> Int {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { throw PhotoLibraryError.accessDenied }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard assets.count > 0 else { return 0 }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
        return assets.count
    }

    static func save(fileAt url: URL, kind: VaultItem.Kind) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotoLibraryError.accessDenied }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: kind == .video ? .video : .photo, fileURL: url, options: nil)
        }
    }
}
