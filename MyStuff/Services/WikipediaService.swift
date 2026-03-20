import Foundation
import CoreLocation

struct WikiSummary {
    let title: String
    let extract: String
    let pageURL: URL?
}

enum WikipediaService {
    private static let languages = ["he", "en"]

    /// Fetches a Wikipedia summary from a direct Wikipedia URL (any language).
    static func fetchSummary(wikiURL urlString: String) async -> WikiSummary? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host,
              host.hasSuffix(".wikipedia.org"),
              let lang = host.components(separatedBy: ".").first,
              url.path.hasPrefix("/wiki/") else { return nil }
        let title = String(url.path.dropFirst("/wiki/".count))
        return await fetchSummaryByTitle(title, lang: lang)
    }

    /// Fetches a Wikipedia summary for a place.
    /// Tries geo-search (English then Hebrew), then name search (English then Hebrew).
    static func fetchSummary(name: String, coordinate: CLLocationCoordinate2D? = nil) async -> WikiSummary? {
        if let coord = coordinate {
            for lang in languages {
                if let title = await geoSearchTitle(lat: coord.latitude, lon: coord.longitude, lang: lang),
                   let summary = await fetchSummaryByTitle(title, lang: lang) {
                    return summary
                }
            }
        }
        for lang in languages {
            if let title = await searchTitle(query: name, lang: lang),
               let summary = await fetchSummaryByTitle(title, lang: lang) {
                return summary
            }
        }
        return nil
    }

    // MARK: - Private

    private static func geoSearchTitle(lat: Double, lon: Double, lang: String) async -> String? {
        guard let url = URL(string:
            "https://\(lang).wikipedia.org/w/api.php?action=query&list=geosearch" +
            "&gscoord=\(lat)|\(lon)&gsradius=10000&gslimit=1&format=json"
        ) else { return nil }
        guard let data = try? await URLSession.shared.data(from: url).0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? [String: Any],
              let results = query["geosearch"] as? [[String: Any]],
              let title = results.first?["title"] as? String else { return nil }
        return title
    }

    private static func searchTitle(query: String, lang: String) async -> String? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string:
            "https://\(lang).wikipedia.org/w/api.php?action=opensearch&search=\(encoded)&limit=1&format=json"
        ) else { return nil }
        guard let data = try? await URLSession.shared.data(from: url).0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let titles = json[safe: 1] as? [String],
              let first = titles.first else { return nil }
        return first
    }

    private static func fetchSummaryByTitle(_ title: String, lang: String) async -> WikiSummary? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(encoded)") else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let extract = json["extract"] as? String, !extract.isEmpty else { return nil }
        let pageTitle = json["title"] as? String ?? title
        let pageURL = (json["content_urls"] as? [String: Any])
            .flatMap { $0["desktop"] as? [String: Any] }
            .flatMap { $0["page"] as? String }
            .flatMap { URL(string: $0) }
        return WikiSummary(title: pageTitle, extract: extract, pageURL: pageURL)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
