import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Reads, converts and decodes copied images. Everything except `read` may run on a background thread.
enum ClipImages {
    private static let maxPixels = 40_000_000
    private static let maxPngBytes = 30 * 1024 * 1024

    // The popup shows thumbnails at half this size, so they stay sharp on Retina displays.
    private static let thumbnailHeight = 64.0
    private static let thumbnailMaxWidth = 256.0

    /// The image on the pasteboard: the PNG an app put there, or else its TIFF. Must run on the main thread.
    static func read(_ pasteboard: NSPasteboard) -> Data? {
        // PNG (browsers, screenshots) keeps transparency and needs no re-encoding.
        if let png = pasteboard.data(forType: .png), png.count <= maxPngBytes { return png }
        if let tiff = pasteboard.data(forType: .tiff) { return tiff }
        return nil
    }

    /// Turns a copied image into a history item and its data, or returns nil when it is too large or unreadable.
    static func create(_ imageData: Data) -> (ClipItem, ClipData)? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width * height <= maxPixels else { return nil }

        let isPng = (CGImageSourceGetType(source) as String?) == UTType.png.identifier
        guard let png = isPng ? imageData : pngFromSource(source), png.count <= maxPngBytes else { return nil }

        let scale = min(1, min(thumbnailHeight / Double(height), thumbnailMaxWidth / Double(width)))
        let thumbnailSize = max(1, Int((Double(max(width, height)) * scale).rounded()))
        let thumbnail = downscaled(png, maxPixelSize: thumbnailSize).flatMap { encodePng($0) }

        let hash = SHA256.hash(data: png).map { String(format: "%02X", $0) }.joined()
        return (ClipItem(imageHash: hash, width: width, height: height, thumbnail: thumbnail), ClipData(png: png))
    }

    /// Decodes an image, scaled down so its longest side is at most `maxPixelSize` pixels.
    static func downscaled(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The image as TIFF, which older apps read from the pasteboard.
    static func tiff(_ png: Data) -> Data? {
        decode(png).flatMap { NSBitmapImageRep(cgImage: $0).tiffRepresentation }
    }

    private static func pngFromSource(_ source: CGImageSource) -> Data? {
        CGImageSourceCreateImageAtIndex(source, 0, nil).flatMap { encodePng($0) }
    }

    private static func encodePng(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
