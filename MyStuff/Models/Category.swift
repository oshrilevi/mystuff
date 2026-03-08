import Foundation

struct Category: Identifiable, Equatable {
    let id: String
    var name: String
    var order: Int

    init(id: String = UUID().uuidString, name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }

    static let columnOrder = ["id", "name", "order"]

    /// True when the category name is "Wishlist" (case-insensitive). Used to hide totals, date sort, and quantity/purchase date in UI.
    static func isWishlist(_ name: String) -> Bool {
        name.caseInsensitiveCompare("Wishlist") == .orderedSame
    }
}
