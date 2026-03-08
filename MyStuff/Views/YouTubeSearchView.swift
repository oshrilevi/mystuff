import SwiftUI

private let youtubePersistedURLKey = "mystuff_youtube_browser_last_url"
private let youtubeBaseURL = URL(string: "https://www.youtube.com")!

struct YouTubeSearchView: View {
    @EnvironmentObject var session: Session
    @StateObject private var webViewState = AmazonWebViewState()
    @State private var urlBarText: String = ""

    private var initialURL: URL {
        if let query = session.youtubeSearchQuery, !query.isEmpty,
           let encoded = query.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: " &="))) {
            return URL(string: "https://www.youtube.com/results?search_query=\(encoded)") ?? youtubeBaseURL
        }
        if let saved = UserDefaults.standard.string(forKey: youtubePersistedURLKey), let url = URL(string: saved) {
            return url
        }
        return youtubeBaseURL
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            AmazonWebViewRepresentable(initialURL: initialURL, persistedURLKey: youtubePersistedURLKey, state: webViewState)
        }
        .onAppear {
            if session.youtubeSearchQuery != nil {
                session.youtubeSearchQuery = nil
            }
            urlBarText = webViewState.currentURLString ?? initialURL.absoluteString
        }
        .onChange(of: webViewState.currentURLString) { _, newValue in
            urlBarText = newValue ?? ""
        }
        .navigationTitle("YouTube")
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button { webViewState.goBack?() } label: {
                Image(systemName: "chevron.left")
            }
            .help("Back")
            .disabled(!webViewState.canGoBack)

            Button { webViewState.goForward?() } label: {
                Image(systemName: "chevron.right")
            }
            .help("Forward")
            .disabled(!webViewState.canGoForward)

            Button { webViewState.reload?() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload")

            TextField("URL", text: $urlBarText, prompt: Text("https://"))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
                .onSubmit { loadURLFromBar() }
                .frame(minWidth: 0, maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func loadURLFromBar() {
        var raw = urlBarText.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return }
        if !raw.contains("://") {
            raw = "https://" + raw
        }
        guard let url = URL(string: raw), url.scheme == "https" || url.scheme == "http" else { return }
        webViewState.loadURL?(url)
    }
}
