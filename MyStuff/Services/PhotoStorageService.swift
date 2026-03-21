import Foundation
import PhotosUI
import SwiftUI

/// Stores a reference to an existing Photos library asset when possible; otherwise
/// saves image data to disk as a fallback (e.g. for photos picked outside Photos.app).
enum PhotoStorageService {
    /// Returns a storage identifier for the given picker item.
    /// Prefers the PHAsset local identifier (no file copy). Falls back to saving
    /// image data to `Documents/mystuff_photos/` and returning a filename.
    static func save(item: PhotosPickerItem) async -> String? {
        // Prefer PHAsset reference — no copy needed
        if let identifier = item.itemIdentifier {
            return identifier
        }
        // Fallback: load raw data and persist to disk
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("mystuff_photos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        guard (try? data.write(to: url)) != nil else { return nil }
        return filename
    }

    /// Returns the file URL for a legacy photo stored in `Documents/mystuff_photos/`.
    static func legacyURL(for filename: String) -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("mystuff_photos/\(filename)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
