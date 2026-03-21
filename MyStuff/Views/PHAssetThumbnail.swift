import SwiftUI
import Photos

#if os(iOS)
private typealias PlatformImage = UIImage
#else
private typealias PlatformImage = NSImage
#endif

/// Loads and displays a photo referenced by its PHAsset local identifier,
/// or by a legacy filename stored in Documents/mystuff_photos/.
struct PHAssetThumbnail: View {
    let identifier: String
    var size: CGFloat = 72

    @State private var image: Image? = nil

    /// Legacy identifiers are plain filenames like "UUID.jpg" (no "/" path separator).
    /// PHAsset local identifiers always contain "/" (e.g. "UUID/L0/001").
    private var isLegacy: Bool { !identifier.contains("/") && identifier.contains(".") }

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.secondary.opacity(0.1)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .onTapGesture { openInPhotos() }
        .help("Click to open in Photos")
        .task(id: identifier) {
            image = await loadThumbnail()
        }
    }

    private func openInPhotos() {
        if isLegacy {
            guard let url = PhotoStorageService.legacyURL(for: identifier) else { return }
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            if let photosURL = URL(string: "photos-redirect://") {
                UIApplication.shared.open(photosURL)
            }
            #endif
            return
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return }
        #if os(macOS)
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = false
        asset.requestContentEditingInput(with: options) { input, _ in
            guard let url = input?.fullSizeImageURL else { return }
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        #else
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func loadThumbnail() async -> Image? {
        if isLegacy {
            return loadLegacyThumbnail()
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let targetSize = CGSize(width: size * 2, height: size * 2)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { platformImage, info in
                // Skip degraded (low-res preview) callbacks; wait for the full-quality one.
                // If the key is absent (nil), treat as non-degraded so we always resume.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                guard !resumed else { return }
                resumed = true
                guard let platformImage else {
                    continuation.resume(returning: nil)
                    return
                }
                #if os(iOS)
                continuation.resume(returning: Image(uiImage: platformImage))
                #else
                continuation.resume(returning: Image(nsImage: platformImage))
                #endif
            }
        }
    }

    private func loadLegacyThumbnail() -> Image? {
        guard let url = PhotoStorageService.legacyURL(for: identifier) else { return nil }
        #if os(iOS)
        guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: uiImage)
        #else
        guard let nsImage = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: nsImage)
        #endif
    }
}
