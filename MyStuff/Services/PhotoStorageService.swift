import Foundation
import SwiftUI
import PhotosUI

enum PhotoStorageService {
    static var photosDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("mystuff_photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(item: PhotosPickerItem) async -> String? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
        let filename = UUID().uuidString + "." + ext
        let url = photosDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
        return FileManager.default.fileExists(atPath: url.path) ? filename : nil
    }

    static func url(for filename: String) -> URL? {
        guard !filename.isEmpty else { return nil }
        let url = photosDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func delete(filename: String) {
        guard let url = url(for: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
