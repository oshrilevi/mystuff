import SwiftUI

/// Shows a favicon for a given URL (from its domain) with SF Symbol fallback when unavailable.
/// Use for fixed destinations (e.g. YouTube) like StoreIconView/SourceIconView do for stores/sources.
struct FaviconView: View {
    let urlString: String
    var fallbackSystemImage: String = "link"
    var size: CGFloat = 24

    private var faviconURL: URL? {
        guard let host = URL(string: urlString)?.host, !host.isEmpty else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
    }

    var body: some View {
        Group {
            if let url = faviconURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure, .empty:
                        fallbackIcon
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
    }

    private var fallbackIcon: some View {
        Image(systemName: fallbackSystemImage)
            .foregroundStyle(.secondary)
    }
}
