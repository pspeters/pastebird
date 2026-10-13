import Foundation

/// The parts of a clipboard item that are too large for the history file: the formatting of copied text
/// (HTML and RTF) or a copied image (PNG). Stored per item by `LocalStorage` and only loaded
/// when the item is pasted or previewed.
struct ClipData: Codable {
    var html: String?
    var rtf: Data?
    var png: Data?

    func serialize() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    static func deserialize(_ data: Data) throws -> ClipData {
        try PropertyListDecoder().decode(ClipData.self, from: data)
    }
}
