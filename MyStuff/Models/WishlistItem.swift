import Foundation

struct WishlistItem: Identifiable, Equatable {
    let id: String
    var name: String
    var notes: String
    var price: String
    var link: String
    var createdAt: String
    /// Drive file ID of the uploaded photo (one photo per wishlist item).
    var photoId: String
    var tags: [String]

    init(
        id: String = UUID().uuidString,
        name: String = "",
        notes: String = "",
        price: String = "",
        link: String = "",
        createdAt: String = "",
        photoId: String = "",
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.price = price
        self.link = link
        self.createdAt = createdAt.isEmpty ? ISO8601DateFormatter().string(from: Date()) : createdAt
        self.photoId = photoId
        self.tags = tags
    }

    /// Returns price string formatted for display in NIS (e.g. "₪ 99.00" or "—" if empty).
    static func priceInNIS(_ price: String) -> String {
        let trimmed = price.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "—" }
        return "₪ \(trimmed)"
    }

    static let columnOrder = ["id", "name", "notes", "price", "link", "createdAt", "photoId", "tags"]
}
