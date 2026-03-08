import SwiftUI

/// Shows a source's favicon (from its URL domain) with SF Symbol "link" fallback when unavailable.
struct SourceIconView: View {
    let source: UserSource
    var size: CGFloat = 24

    private var faviconURL: URL? {
        guard let host = URL(string: source.url)?.host, !host.isEmpty else { return nil }
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
        Image(systemName: "link")
            .foregroundStyle(.secondary)
    }
}
