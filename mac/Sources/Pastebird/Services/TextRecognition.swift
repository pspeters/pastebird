import Foundation
import Vision

/// Reads the text in copied images with the text recognition built into macOS (Vision), so screenshots can be
/// found by the words on them. Runs on this Mac, without internet.
enum TextRecognition {
    private static let maxChars = 20_000

    /// The text in the image, one line per line of text; "" when there is none. Nil when it couldn't be read.
    /// Slow for large images: call it on a background queue.
    static func recognize(_ png: Data) -> String? {
        guard let image = ClipImages.decode(png) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            LocalStorage.log(error)
            return nil
        }
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(maxChars))
    }
}
