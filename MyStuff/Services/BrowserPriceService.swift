import Foundation
import WebKit

/// Loads a product URL in a headless WKWebView, lets the page render (including JavaScript),
/// then extracts the current price via injected JavaScript. Use for sites that block simple HTTP
/// requests or render price with JS (e.g. Amazon).
@MainActor
final class BrowserPriceService: NSObject {
    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private let navigationTimeout: TimeInterval = 20
    private let postLoadDelay: TimeInterval = 2.5  // extra wait for JS-rendered price (e.g. Amazon)

    private struct LoadError: Error {}

    private static let priceExtractionScript = """
    (function() {
        function trim(s) { return (s && s.trim) ? s.trim() : ''; }
        function looksLikePrice(s) {
            if (!s || typeof s !== 'string') return false;
            var t = trim(s).replace(/[,$€£¥₪]/g, '').replace(/\\s/g, '');
            return /^\\d+(\\.\\d{1,2})?$/.test(t) || /^\\d{1,3}(,\\d{3})*(\\.\\d{1,2})?$/.test(t);
        }
        function firstPrice(candidates) {
            for (var i = 0; i < candidates.length; i++) {
                var v = candidates[i];
                if (v && looksLikePrice(v)) return trim(String(v));
            }
            return null;
        }
        var price = null;
        var meta = document.querySelector('meta[property="product:price:amount"]');
        if (meta && meta.content) price = firstPrice([meta.content]);
        if (price) return price;
        var scripts = document.querySelectorAll('script[type="application/ld+json"]');
        for (var i = 0; i < scripts.length; i++) {
            try {
                var json = JSON.parse(scripts[i].textContent);
                var obj = Array.isArray(json) ? json[0] : json;
                if (obj && (obj['@type'] === 'Product' || obj['@type'] === 'http://schema.org/Product')) {
                    if (obj.price) price = firstPrice([obj.price]);
                    if (!price && obj.offers) {
                        var offers = Array.isArray(obj.offers) ? obj.offers : [obj.offers];
                        if (offers[0] && offers[0].price) price = firstPrice([offers[0].price]);
                    }
                    if (price) return price;
                }
            } catch (e) {}
        }
        var sel = [
            'span.apexPriceToPay .a-offscreen',
            'span.a-price.a-text-price .a-offscreen',
            '#corePrice_desktop .a-offscreen',
            '.a-price .a-offscreen',
            'span.priceToPay .a-offscreen',
            '#priceblock_ourprice',
            '#priceblock_dealprice',
            '.priceBlockBuyingPriceString',
            '[data-a-color="price"] .a-offscreen',
            '.a-price-whole',
            '#corePrice_feature_div .a-offscreen',
            '.product-price',
            '.price',
            '#price'
        ];
        for (var j = 0; j < sel.length; j++) {
            var el = document.querySelector(sel[j]);
            if (el) {
                var text = el.innerText || el.textContent;
                if (text) price = firstPrice([text]);
                if (price) return price;
            }
        }
        return null;
    })();
    """

    /// Loads the URL in a hidden web view, waits for load + JS, runs extraction script, returns price string or nil.
    func extractPrice(from url: URL) async -> String? {
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        let wv: WKWebView
        if let existing = webView {
            wv = existing
        } else {
            let config = WKWebViewConfiguration()
            config.processPool = WKProcessPool()
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")
            wv = WKWebView(frame: .zero, configuration: config)
            wv.navigationDelegate = self
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.15"
            webView = wv
        }

        loadContinuation = nil
        wv.load(URLRequest(url: url))

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                loadContinuation = cont
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(self.navigationTimeout * 1_000_000_000))
                    let c = self.loadContinuation
                    self.loadContinuation = nil
                    c?.resume(throwing: LoadError())
                }
            }
        } catch {
            return nil
        }

        try? await Task.sleep(nanoseconds: UInt64(postLoadDelay * 1_000_000_000))

        let raw = await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            wv.evaluateJavaScript(BrowserPriceService.priceExtractionScript) { result, _ in
                let s = (result as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                cont.resume(returning: s?.isEmpty == false ? s : nil)
            }
        }
        return raw.map { Self.normalizePriceString($0) }
    }

    /// Keeps digits and one decimal point so Item.formattedPrice displays correctly.
    private static func normalizePriceString(_ s: String) -> String {
        var t = s
        for c in ["$", "€", "£", "¥", "₪", ",", " "] { t = t.replacingOccurrences(of: c, with: "") }
        if t.contains(".") {
            let parts = t.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count == 2, parts[1].count <= 2 {
                return String(parts[0].filter(\.isNumber)) + "." + String(parts[1].filter(\.isNumber))
            }
        }
        return String(t.filter { $0.isNumber || $0 == "." })
    }

    private func finishLoad(success: Bool) {
        let c = loadContinuation
        loadContinuation = nil
        if success {
            c?.resume(returning: ())
        } else {
            c?.resume(throwing: LoadError())
        }
    }
}

extension BrowserPriceService: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            finishLoad(success: true)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            finishLoad(success: false)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            finishLoad(success: false)
        }
    }
}
