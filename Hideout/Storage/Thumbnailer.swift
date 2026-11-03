import UIKit
import ImageIO
import AVFoundation

enum Thumbnailer {
    static let thumbnailPixelSize = 360

    /// A small JPEG for the grid.
    static func photoThumbnail(from data: Data) -> Data? {
        downsampledImage(from: data, maxPixelSize: thumbnailPixelSize)?.jpegData(compressionQuality: 0.8)
    }

    /// Decodes an image at a reduced size, which is much faster and lighter than full size.
    static func downsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    static func videoThumbnail(for url: URL) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbnailPixelSize, height: thumbnailPixelSize)
        guard let result = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: result.image).jpegData(compressionQuality: 0.8)
    }

    static func videoDuration(for url: URL) async -> Double? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return nil }
        let seconds = duration.seconds
        return seconds.isFinite ? seconds : nil
    }
}
