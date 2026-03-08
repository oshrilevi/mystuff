import SwiftUI

struct SourceBrowserView: View {
    let source: UserSource

    @StateObject private var webViewState = AmazonWebViewState()
    @State private var urlBarText: String = ""

    private var initialURL: URL {
        (UserDefaults.standard.string(forKey: source.persistedURLKey)).flatMap { URL(string: $0) } ?? source.urlAsURL
    }

    private var openInChromeURL: URL? {
        guard let s = webViewState.currentURLString,
              let url = URL(string: s),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            AmazonWebViewRepresentable(initialURL: initialURL, persistedURLKey: source.persistedURLKey, state: webViewState)
        }
        .onChange(of: webViewState.currentURLString) { _, newValue in
            urlBarText = newValue ?? ""
        }
        .onAppear {
            urlBarText = webViewState.currentURLString ?? initialURL.absoluteString
        }
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

            Button {
                guard let url = openInChromeURL else { return }
                OpenInBrowser.openInChromeOrDefault(url)
            } label: {
                Image(systemName: "arrow.up.forward")
            }
            .help("Open in Chrome")
            .accessibilityLabel("Open in Chrome")
            .disabled(openInChromeURL == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
