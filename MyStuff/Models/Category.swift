import Foundation

struct Category: Identifiable, Equatable {
    let id: String
    var name: String
    var order: Int
    /// Optional hex color for the category (e.g. "#FF5733"). Used as section header background in items list.
    var color: String?

    init(id: String = UUID().uuidString, name: String, order: Int = 0, color: String? = nil) {
        self.id = id
        self.name = name
        self.order = order
        self.color = color
    }

    static let columnOrder = ["id", "name", "order", "color"]

    /// True when the category name is "Wishlist" (case-insensitive). Used to hide totals, date sort, and quantity/purchase date in UI.
    static func isWishlist(_ name: String) -> Bool {
        name.caseInsensitiveCompare("Wishlist") == .orderedSame
    }
}
