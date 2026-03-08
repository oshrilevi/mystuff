import Foundation

struct UserStore: Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var startURL: String
    var order: Int
    var systemImage: String

    init(id: String = UUID().uuidString, name: String, startURL: String, order: Int = 0, systemImage: String = "link") {
        self.id = id
        self.name = name
        self.startURL = startURL
        self.order = order
        self.systemImage = systemImage
    }

    /// URL for the in-app browser; invalid URLs fall back to a safe default.
    var startURLAsURL: URL {
        URL(string: startURL).flatMap { ($0.scheme == "https" || $0.scheme == "http") ? $0 : nil }
            ?? URL(string: "https://")!
    }

    /// UserDefaults key for persisting last-visited URL for this store.
    var persistedURLKey: String {
        "mystuff_browser_\(id)"
    }

    static let columnOrder = ["id", "name", "startURL", "order", "systemImage"]
}
