import Foundation

/// Lightweight helper for deriving a thumbnail URL for Amazon products.
/// Uses `PageMetadataService` to read the product page's Open Graph image.
final class AmazonThumbnailService {
    private let pageMetadata: PageMetadataService

    /// In-memory cache so repeated lookups for the same product are cheap.
    /// Key is a stable identifier built from host + ASIN.
    private var cache: [String: URL?] = [:]

    init(pageMetadata: PageMetadataService) {
        self.pageMetadata = pageMetadata
    }

    /// Returns a thumbnail URL for the given Amazon ASIN, if one can be derived.
    /// - Parameters:
    ///   - asin: The product ASIN from the Amazon CSV.
    ///   - website: The Website field from the CSV (e.g. "www.amazon.com").
    func thumbnailURL(forASIN asin: String, website: String) async -> URL? {
        let trimmedASIN = asin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedASIN.isEmpty else { return nil }

        let host = normalizedHost(from: website)
        let cacheKey = "\(host)|\(trimmedASIN)"
        if let cached = cache[cacheKey] {
            return cached
        }

        guard let productURL = URL(string: "https://\(host)/dp/\(trimmedASIN)") else {
            cache[cacheKey] = nil
            return nil
        }

        do {
            let metadata = try await pageMetadata.fetchMetadata(from: productURL)
            if let imageString = metadata.imageURL,
               let url = URL(string: imageString.trimmingCharacters(in: .whitespacesAndNewlines)),
               !url.absoluteString.isEmpty {
                cache[cacheKey] = url
                return url
            }
        } catch {
            // Ignore errors; fall through to nil.
        }

        cache[cacheKey] = nil
        return nil
    }

    private func normalizedHost(from website: String) -> String {
        let trimmed = website.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "www.amazon.com"
        }
        if let url = URL(string: trimmed), let host = url.host {
            return host
        }
        // If user gives something like "www.amazon.de" without scheme, keep as-is.
        return trimmed
    }
}

