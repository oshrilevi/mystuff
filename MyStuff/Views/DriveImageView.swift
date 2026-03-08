import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Loads and displays an image from Google Drive using authenticated request.
/// Use this instead of AsyncImage + thumbnail URL, since Drive thumbnail URLs require auth.
struct DriveImageView: View {
    let drive: DriveService
    let fileId: String
    var contentMode: SwiftUI.ContentMode = .fit
    /// When set, called on the main actor with the detected background color after the image loads (for thumbnail fill).
    var onBackgroundColorDetected: ((Color?) -> Void)? = nil

    @State private var imageData: Data?
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else if let data = imageData {
                imageFromData(data)
            } else {
                ProgressView()
            }
        }
        .task(id: fileId) {
            guard imageData == nil, !failed else { return }
            do {
                imageData = try await drive.fetchImageData(fileId: fileId)
            } catch {
                failed = true
            }
        }
        .onChange(of: imageData) { _, newValue in
            guard let data = newValue, let callback = onBackgroundColorDetected else { return }
            let id = fileId
            Task.detached(priority: .userInitiated) {
                let rgb = ImageBackgroundColorSampler.sampleBackgroundRGB(from: data, fileId: id)
                let color = rgb.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
                await MainActor.run { callback(color) }
            }
        }
    }

    @ViewBuilder
    private func imageFromData(_ data: Data) -> some View {
        #if os(iOS)
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
        #elseif os(macOS)
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
        #else
        Image(systemName: "photo")
        #endif
    }
}
