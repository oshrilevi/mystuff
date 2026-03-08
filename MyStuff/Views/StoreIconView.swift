import SwiftUI

/// Shows a store's favicon (from its start URL domain) with SF Symbol fallback when unavailable.
struct StoreIconView: View {
    let store: UserStore
    var size: CGFloat = 24

    private var faviconURL: URL? {
        guard let host = URL(string: store.startURL)?.host, !host.isEmpty else { return nil }
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
        Image(systemName: store.systemImage)
            .foregroundStyle(.secondary)
    }
}
