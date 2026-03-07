import Foundation

struct PageMetadata {
    var title: String?
    var description: String?
    var imageURL: String?
    var price: String?
}

enum PageMetadataError: LocalizedError {
    case invalidURL
    case requestFailed(String)
    case nonHTTPResponse
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .requestFailed(let msg): return msg
        case .nonHTTPResponse: return "Invalid response"
        case .badStatus(let code): return "Request failed (HTTP \(code))"
        }
    }
}

final class PageMetadataService {
    private let timeout: TimeInterval = 15
    private let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    func fetchMetadata(from url: URL) async throws -> PageMetadata {
        guard url.scheme == "https" || url.scheme == "http" else {
            throw PageMetadataError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PageMetadataError.nonHTTPResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw PageMetadataError.badStatus(http.statusCode)
        }

        let html = String(data: data, encoding: .utf8) ?? ""
        return parseMetadata(from: html)
    }

    private func parseMetadata(from html: String) -> PageMetadata {
        var title: String?
        var description: String?
        var imageURL: String?
        var price: String?

        // Open Graph
        title = title ?? valueForMeta(html, property: "og:title")
        description = description ?? valueForMeta(html, property: "og:description")
        imageURL = imageURL ?? valueForMeta(html, property: "og:image")
        price = price ?? valueForMeta(html, property: "product:price:amount")

        // Fallback: standard meta name
        if title == nil { title = valueForMetaName(html, name: "title") }
        if description == nil { description = valueForMetaName(html, name: "description") }

        // JSON-LD Product (simple scan for "name" and "offers" near "@type":"Product")
        if title == nil || price == nil, let product = parseJSONLDProduct(from: html) {
            if title == nil { title = product.name }
            if description == nil { description = product.description }
            if imageURL == nil { imageURL = product.image }
            if price == nil { price = product.price }
        }

        return PageMetadata(
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title : nil,
            description: description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? description : nil,
            imageURL: imageURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? imageURL : nil,
            price: price?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? price : nil
        )
    }

    private func valueForMeta(_ html: String, property: String) -> String? {
        // Support content before or after property
        let contentFirst = #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+property\s*=\s*["']\#(property)["']"#
        if let v = firstCapture(html: html, pattern: contentFirst) { return v }
        let propertyFirst = #"<meta[^>]+property\s*=\s*["']\#(property)["'][^>]+content\s*=\s*["']([^"']+)["']"#
        return firstCapture(html: html, pattern: propertyFirst)
    }

    private func valueForMetaName(_ html: String, name: String) -> String? {
        let pattern = #"<meta[^>]+name\s*=\s*["']\#(name)["'][^>]+content\s*=\s*["']([^"']+)["']"#
        if let v = firstCapture(html: html, pattern: pattern) { return v }
        let pattern2 = #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+name\s*=\s*["']\#(name)["']"#
        return firstCapture(html: html, pattern: pattern2)
    }

    private func firstCapture(html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[captureRange])
    }

    private struct JSONLDProduct {
        var name: String?
        var description: String?
        var image: String?
        var price: String?
    }

    private func parseJSONLDProduct(from html: String) -> JSONLDProduct? {
        // Find script type="application/ld+json" blocks and look for "@type":"Product"
        let scriptPattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let scriptRegex = try? NSRegularExpression(pattern: scriptPattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        let matches = scriptRegex.matches(in: html, options: [], range: range)
        for match in matches {
            guard match.numberOfRanges > 1, let blockRange = Range(match.range(at: 1), in: html) else { continue }
            let block = String(html[blockRange])
            if !block.contains("\"@type\"") { continue }
            if block.range(of: "Product", options: .caseInsensitive) == nil { continue }
            return extractProductFromJSONLDBlock(block)
        }
        return nil
    }

    private func extractProductFromJSONLDBlock(_ block: String) -> JSONLDProduct? {
        // Minimal extraction: look for "name": "...", "description": "...", "image": "..." or ["..."], "price": ...
        func extractString(for key: String) -> String? {
            // "name":"value" or "name": "value"
            let patterns = [
                "\"\(key)\"\\s*:\\s*\"([^\"]+)\"",
                "\"\(key)\"\\s*:\\s*\\[\\s*\"([^\"]+)\""
            ]
            for p in patterns {
                if let v = firstCapture(html: block, pattern: p) { return v }
            }
            return nil
        }
        func extractPrice(from block: String) -> String? {
            if let p = extractString(for: "price") { return p }
            // "offers": { "price": "..." } or "offers": [{ "price": ... }]
            let offerPattern = "\"offers\"\\s*:\\s*\\{\\s*\"price\"\\s*:\\s*\"([^\"]+)\""
            if let v = firstCapture(html: block, pattern: offerPattern) { return v }
            let offerArrayPattern = "\"offers\"\\s*:\\s*\\[\\s*\\{\\s*\"price\"\\s*:\\s*\"([^\"]+)\""
            return firstCapture(html: block, pattern: offerArrayPattern)
        }
        let name = extractString(for: "name")
        let description = extractString(for: "description")
        let image = extractString(for: "image")
        let price = extractPrice(from: block)
        if name == nil && description == nil && image == nil && price == nil { return nil }
        return JSONLDProduct(name: name, description: description, image: image, price: price)
    }
}
