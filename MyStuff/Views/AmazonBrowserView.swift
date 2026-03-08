import SwiftUI
import WebKit

// MARK: - Web view state (current URL and navigation actions)

@MainActor
final class AmazonWebViewState: ObservableObject {
    @Published var currentURLString: String?
    @Published var canGoBack = false
    @Published var canGoForward = false

    var goBack: (() -> Void)?
    var goForward: (() -> Void)?
    var reload: (() -> Void)?
}

// MARK: - WKWebView wrapper (iOS)

#if os(iOS)
private struct AmazonWebViewRepresentable: UIViewRepresentable {
    let initialURL: URL
    @ObservedObject var state: AmazonWebViewState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: initialURL))
        context.coordinator.webView = webView
        context.coordinator.installNavigationActions()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        context.coordinator.installNavigationActions()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: AmazonWebViewState
        weak var webView: WKWebView?

        init(state: AmazonWebViewState) {
            self.state = state
        }

        func installNavigationActions() {
            guard let wv = webView else { return }
            state.goBack = { [weak wv] in wv?.goBack() }
            state.goForward = { [weak wv] in wv?.goForward() }
            state.reload = { [weak wv] in wv?.reload() }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                state.currentURLString = webView.url?.absoluteString
                state.canGoBack = webView.canGoBack
                state.canGoForward = webView.canGoForward
                if let urlString = webView.url?.absoluteString, !urlString.isEmpty {
                    UserDefaults.standard.set(urlString, forKey: AmazonBrowserView.persistedURLKey)
                }
            }
        }
    }
}
#endif

// MARK: - WKWebView wrapper (macOS)

#if os(macOS)
private struct AmazonWebViewRepresentable: NSViewRepresentable {
    let initialURL: URL
    @ObservedObject var state: AmazonWebViewState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: initialURL))
        context.coordinator.webView = webView
        context.coordinator.installNavigationActions()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        context.coordinator.installNavigationActions()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: AmazonWebViewState
        weak var webView: WKWebView?

        init(state: AmazonWebViewState) {
            self.state = state
        }

        func installNavigationActions() {
            guard let wv = webView else { return }
            state.goBack = { [weak wv] in wv?.goBack() }
            state.goForward = { [weak wv] in wv?.goForward() }
            state.reload = { [weak wv] in wv?.reload() }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                state.currentURLString = webView.url?.absoluteString
                state.canGoBack = webView.canGoBack
                state.canGoForward = webView.canGoForward
                if let urlString = webView.url?.absoluteString, !urlString.isEmpty {
                    UserDefaults.standard.set(urlString, forKey: AmazonBrowserView.persistedURLKey)
                }
            }
        }
    }
}
#endif

// MARK: - Sheet item for "Add from URL"

private struct AddFromURLItem: Identifiable {
    let id = UUID()
    let urlString: String
}

// MARK: - Amazon browser view

struct AmazonBrowserView: View {
    static let persistedURLKey = "mystuff_amazon_browser_last_url"

    @EnvironmentObject var session: Session
    @StateObject private var webViewState = AmazonWebViewState()
    @State private var addFromURLItem: AddFromURLItem?

    private static let startURL = URL(string: "https://www.amazon.com")!

    private var initialURL: URL {
        (UserDefaults.standard.string(forKey: Self.persistedURLKey)).flatMap { URL(string: $0) } ?? Self.startURL
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            AmazonWebViewRepresentable(initialURL: initialURL, state: webViewState)
        }
        .sheet(item: $addFromURLItem) { item in
            ItemFormView(mode: .add(initialWebLink: item.urlString))
                .environmentObject(session)
                .onDisappear {
                    addFromURLItem = nil
                    Task { await session.inventory.refresh() }
                }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button { webViewState.goBack?() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!webViewState.canGoBack)

            Button { webViewState.goForward?() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!webViewState.canGoForward)

            Button { webViewState.reload?() } label: {
                Image(systemName: "arrow.clockwise")
            }

            Spacer()

            Button {
                if let url = webViewState.currentURLString, !url.isEmpty {
                    addFromURLItem = AddFromURLItem(urlString: url)
                }
            } label: {
                Label("Add this item", systemImage: "plus.circle.fill")
            }
            .disabled(webViewState.currentURLString?.isEmpty ?? true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
