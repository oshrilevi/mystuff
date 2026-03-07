import Foundation

struct Item: Identifiable, Equatable {
    let id: String
    var name: String
    var description: String
    var categoryId: String
    var price: String
    var purchaseDate: String // ISO8601 or YYYY-MM-DD
    var condition: String
    /// Number of copies of this item. Default is 1.
    var quantity: Int
    var createdAt: String
    var updatedAt: String
    var photoIds: [String] // Drive file IDs
    var webLink: String
    var tags: [String]

    init(
        id: String = UUID().uuidString,
        name: String = "",
        description: String = "",
        categoryId: String = "",
        price: String = "",
        purchaseDate: String = "",
        condition: String = "",
        quantity: Int = 1,
        createdAt: String = "",
        updatedAt: String = "",
        photoIds: [String] = [],
        webLink: String = "",
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.categoryId = categoryId
        self.price = price
        self.purchaseDate = purchaseDate
        self.condition = condition
        self.quantity = max(1, quantity)
        self.createdAt = createdAt.isEmpty ? ISO8601DateFormatter().string(from: Date()) : createdAt
        self.updatedAt = updatedAt.isEmpty ? ISO8601DateFormatter().string(from: Date()) : updatedAt
        self.photoIds = photoIds
        self.webLink = webLink
        self.tags = tags
    }

    static let conditionPresets = ["New", "Like new", "Good", "Fair", "Poor"]

    /// Returns price string formatted for display in NIS (e.g. "₪ 99.00" or "—" if empty).
    static func priceInNIS(_ price: String) -> String {
        let trimmed = price.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "—" }
        return "₪ \(trimmed)"
    }

    static let columnOrder = [
        "id", "name", "description", "categoryId", "price", "purchaseDate", "condition", "quantity",
        "createdAt", "updatedAt", "photoIds", "webLink", "tags"
    ]
}
