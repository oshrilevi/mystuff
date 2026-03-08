import Foundation

struct PageMetadata {
    var title: String?
    var description: String?
    var imageURL: String?
    var price: String?
    /// Keywords/tags from meta keywords, og:keywords, or JSON-LD.
    var tags: [String]
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
        return parseMetadata(from: html, url: url)
    }

    private func parseMetadata(from html: String, url: URL) -> PageMetadata {
        var title: String?
        var description: String?
        var imageURL: String?
        var price: String?
        var tags: [String] = []

        // Open Graph
        title = title ?? valueForMeta(html, property: "og:title")
        description = description ?? valueForMeta(html, property: "og:description")
        imageURL = imageURL ?? valueForMeta(html, property: "og:image")
        price = price ?? valueForMeta(html, property: "product:price:amount")
        if let kw = valueForMeta(html, property: "og:keywords") {
            tags.append(contentsOf: parseKeywordsString(kw))
        }

        // All article:tag (multiple meta tags; common on news and product pages)
        tags.append(contentsOf: allValuesForMeta(html, property: "article:tag"))

        // Standard meta name
        if title == nil { title = valueForMetaName(html, name: "title") }
        if description == nil { description = valueForMetaName(html, name: "description") }
        if let kw = valueForMetaName(html, name: "keywords"), !kw.isEmpty {
            tags.append(contentsOf: parseKeywordsString(kw))
        }
        if let newsKw = valueForMetaName(html, name: "news_keywords"), !newsKw.isEmpty {
            tags.append(contentsOf: parseKeywordsString(newsKw))
        }

        // JSON-LD Product / Article
        if let product = parseJSONLDProduct(from: html) {
            if title == nil { title = product.name }
            if description == nil { description = product.description }
            if imageURL == nil { imageURL = product.image }
            if price == nil { price = product.price }
            if let productTags = product.keywords { tags.append(contentsOf: productTags) }
            if let cat = product.category { tags.append(contentsOf: cat) }
        }

        tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        tags = Array(Set(tags))

        // Fallback: derive tags from title and URL when no meta tags found (many sites omit keywords)
        if tags.isEmpty {
            if let t = title ?? valueForMeta(html, property: "og:title") {
                tags = meaningfulWords(from: t)
            }
            if tags.isEmpty, let pathTags = tagsFromURLPath(url) {
                tags = pathTags
            }
        }

        let cleanedTitle = title.map { cleanVendorPhrases(from: $0) }
        let cleanedDescription = description.map { cleanVendorPhrases(from: $0) }

        return PageMetadata(
            title: cleanedTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? cleanedTitle : nil,
            description: cleanedDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? cleanedDescription : nil,
            imageURL: imageURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? imageURL : nil,
            price: price?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? price : nil,
            tags: tags
        )
    }

    /// Splits a comma- or semicolon-separated keywords string into trimmed, non-empty strings.
    private func parseKeywordsString(_ raw: String) -> [String] {
        let separated = raw.split(separator: ",").flatMap { $0.split(separator: ";") }
        return separated.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Returns all content values for meta tags with the given property (e.g. article:tag).
    private func allValuesForMeta(_ html: String, property: String) -> [String] {
        let contentFirst = #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+property\s*=\s*["']\#(property)["']"#
        let propertyFirst = #"<meta[^>]+property\s*=\s*["']\#(property)["'][^>]+content\s*=\s*["']([^"']+)["']"#
        var result: [String] = []
        for pattern in [contentFirst, propertyFirst] {
            result.append(contentsOf: allCaptures(html: html, pattern: pattern))
        }
        return result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func allCaptures(html: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)
        return matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[captureRange])
        }
    }

    /// Removes common vendor boilerplate from title/description (e.g. Amazon prefixes and suffixes).
    private func cleanVendorPhrases(from text: String) -> String {
        var result = text
        let phrasesToRemove = [
            "Amazon.com: ",
            "Buy ",
            "- Amazon.com ✓ FREE DELIVERY possible on eligible purchases"
        ]
        for phrase in phrasesToRemove {
            result = result.replacingOccurrences(of: phrase, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Heuristic: split title into words and keep likely meaningful ones (brands, product terms).
    private func meaningfulWords(from title: String) -> [String] {
        let stopWords: Set<String> = ["the", "a", "an", "and", "or", "for", "with", "in", "on", "at", "to", "of", "by", "is", "–", "-", "|"]
        let words = title.split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 1 && !stopWords.contains($0.lowercased()) }
        return Array(Set(words.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
    }

    /// Extract tag-like segments from URL path (e.g. /products/nikon-z5/ -> ["nikon", "z5"]).
    private func tagsFromURLPath(_ url: URL) -> [String]? {
        let path = url.path
        guard path.count > 1 else { return nil }
        let segments = path.split(separator: "/").filter { !$0.isEmpty }
        let meaningful = segments.flatMap { segment in
            segment.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count > 1 }
        }
        return meaningful.isEmpty ? nil : Array(Set(meaningful))
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
        var keywords: [String]?
        var category: [String]?
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
        var keywords: [String]? = nil
        if let kwArray = extractStringArray(for: "keywords", from: block) {
            keywords = kwArray
        } else if let kw = extractString(for: "keywords") {
            keywords = parseKeywordsString(kw)
        }
        var category: [String]? = nil
        if let catArray = extractStringArray(for: "category", from: block) {
            category = catArray
        } else if let cat = extractString(for: "category") {
            category = [cat]
        }
        if name == nil && description == nil && image == nil && price == nil && keywords == nil && category == nil { return nil }
        return JSONLDProduct(name: name, description: description, image: image, price: price, keywords: keywords, category: category)
    }

    /// Extract string array from JSON: "key": ["a", "b", "c"]
    private func extractStringArray(for key: String, from block: String) -> [String]? {
        // "keywords": ["a", "b", "c"] or "category": ["Electronics", "Cameras"]
        let pattern = "\"\(key)\"\\s*:\\s*\\[([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(block.startIndex..., in: block)
        guard let match = regex.firstMatch(in: block, options: [], range: range), match.numberOfRanges > 1,
              let innerRange = Range(match.range(at: 1), in: block) else { return nil }
        let inner = String(block[innerRange])
        let quoted = #""([^"]+)""#
        guard let innerRegex = try? NSRegularExpression(pattern: quoted) else { return nil }
        let innerNS = NSRange(inner.startIndex..., in: inner)
        let matches = innerRegex.matches(in: inner, options: [], range: innerNS)
        let values = matches.compactMap { m -> String? in
            guard m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: inner) else { return nil }
            return String(inner[r])
        }
        return values.isEmpty ? nil : values
    }
}
