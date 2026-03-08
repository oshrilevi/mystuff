import Foundation

struct UserSource: Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var url: String
    var order: Int

    init(id: String = UUID().uuidString, name: String, url: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.url = url
        self.order = order
    }

    /// URL for the in-app browser; invalid URLs fall back to a safe default.
    var urlAsURL: URL {
        URL(string: url).flatMap { ($0.scheme == "https" || $0.scheme == "http") ? $0 : nil }
            ?? URL(string: "https://")!
    }

    /// UserDefaults key for persisting last-visited URL for this source.
    var persistedURLKey: String {
        "mystuff_browser_source_\(id)"
    }

    static let columnOrder = ["id", "name", "url", "order"]
}
