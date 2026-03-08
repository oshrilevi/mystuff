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
/// WebView that hijacks the context menu "Download Image" so we can save the image URL and download it ourselves
/// (WebKit's default Download Image often does not trigger WKDownloadDelegate on macOS).
private final class AmazonDownloadableWebView: WKWebView {
    var onDownloadImage: ((URL) -> Void)?
    private var pendingImageURL: URL?
    private static let downloadImageIdentifier = "WKMenuItemIdentifierDownloadImage"

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let item = menu.items.first(where: { $0.identifier?.rawValue == Self.downloadImageIdentifier }) else { return }
        item.action = #selector(handleDownloadImage(_:))
        item.target = self
        pendingImageURL = nil
        let point = convert(event.locationInWindow, from: nil)
        let contentY = bounds.height - point.y
        let js = "(function(){ var el = document.elementFromPoint(\(point.x), \(contentY)); return (el && el.tagName === 'IMG') ? el.src : null; })()"
        evaluateJavaScript(js) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let urlString = result as? String, let url = URL(string: urlString) {
                    self.pendingImageURL = url
                }
            }
        }
    }

    @objc private func handleDownloadImage(_ sender: Any?) {
        guard let url = pendingImageURL else { return }
        pendingImageURL = nil
        onDownloadImage?(url)
    }
}

private struct AmazonWebViewRepresentable: NSViewRepresentable {
    let initialURL: URL
    @ObservedObject var state: AmazonWebViewState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = AmazonDownloadableWebView(frame: .zero, configuration: config)
        let coordinator = context.coordinator
        webView.navigationDelegate = coordinator
        webView.load(URLRequest(url: initialURL))
        coordinator.webView = webView
        coordinator.installNavigationActions()
        (webView as? AmazonDownloadableWebView)?.onDownloadImage = { [weak coordinator] url in
            coordinator?.downloadImageToDownloads(url: url)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.webView = webView
        coordinator.installNavigationActions()
        (webView as? AmazonDownloadableWebView)?.onDownloadImage = { [weak coordinator] url in
            coordinator?.downloadImageToDownloads(url: url)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
        let state: AmazonWebViewState
        weak var webView: WKWebView?
        private var activeDownloads: [WKDownload] = []

        init(state: AmazonWebViewState) {
            self.state = state
        }

        func installNavigationActions() {
            guard let wv = webView else { return }
            state.goBack = { [weak wv] in wv?.goBack() }
            state.goForward = { [weak wv] in wv?.goForward() }
            state.reload = { [weak wv] in wv?.reload() }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download, preferences)
            } else {
                decisionHandler(.allow, preferences)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            // When user chooses "Download Image" from context menu, WebKit may load the image in the main frame.
            // Treat main-frame image responses as download so we get a WKDownload and save to Downloads.
            if navigationResponse.isForMainFrame,
               let mimeType = navigationResponse.response.mimeType?.lowercased(),
               mimeType.hasPrefix("image/") {
                decisionHandler(.download)
                return
            }
            if !navigationResponse.canShowMIMEType {
                decisionHandler(.download)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
            activeDownloads.append(download)
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
            activeDownloads.append(download)
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

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                completionHandler(nil)
                return
            }
            var name = (suggestedFilename as NSString).lastPathComponent
            if name.isEmpty || name.contains("..") || name.contains("/") || name.contains("\\") {
                name = "download"
            }
            var destination = downloadsDirectory.appendingPathComponent(name)
            var index = 1
            let pathExtension = destination.pathExtension
            let baseName = destination.deletingPathExtension().lastPathComponent
            while FileManager.default.fileExists(atPath: destination.path) {
                let newName = pathExtension.isEmpty ? "\(baseName)-\(index)" : "\(baseName)-\(index).\(pathExtension)"
                destination = downloadsDirectory.appendingPathComponent(newName)
                index += 1
            }
            completionHandler(destination)
        }

        func downloadDidFinish(_ download: WKDownload) {
            activeDownloads.removeAll { $0 === download }
        }

        /// Download an image (or any URL) to the user's Downloads folder, using the WebView's cookies (e.g. for Amazon).
        func downloadImageToDownloads(url: URL) {
            guard let wv = webView else { return }
            guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
            wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let config = URLSessionConfiguration.default
                let storage = HTTPCookieStorage()
                storage.cookieAcceptPolicy = .always
                cookies.forEach { storage.setCookie($0) }
                config.httpCookieStorage = storage
                let session = URLSession(configuration: config)
                session.downloadTask(with: url) { localURL, _, error in
                    guard let localURL = localURL, error == nil else { return }
                    var name = (url.lastPathComponent as NSString).lastPathComponent
                    if name.isEmpty || name.contains("..") || name.contains("/") || name.contains("\\") { name = "download" }
                    var destination = downloadsDirectory.appendingPathComponent(name)
                    var index = 1
                    let pathExtension = destination.pathExtension
                    let baseName = destination.deletingPathExtension().lastPathComponent
                    while FileManager.default.fileExists(atPath: destination.path) {
                        let newName = pathExtension.isEmpty ? "\(baseName)-\(index)" : "\(baseName)-\(index).\(pathExtension)"
                        destination = downloadsDirectory.appendingPathComponent(newName)
                        index += 1
                    }
                    try? FileManager.default.moveItem(at: localURL, to: destination)
                }.resume()
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
