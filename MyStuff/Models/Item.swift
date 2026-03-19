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
    var locationId: String
    /// Currency for price when item is in Wishlist: "NIS", "USD", or "" (treated as NIS). Ignored for non-Wishlist categories.
    var priceCurrency: String

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
        tags: [String] = [],
        locationId: String = "",
        priceCurrency: String = ""
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
        self.locationId = locationId
        self.priceCurrency = priceCurrency
    }

    static let conditionPresets = ["New", "Like new", "Good", "Fair", "Poor"]

    /// Returns price string formatted for display in NIS (e.g. "₪ 99.00" or "—" if empty).
    static func priceInNIS(_ price: String) -> String {
        let trimmed = price.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "—" }
        return "₪ \(trimmed)"
    }

    /// Returns price string for display: USD symbol when priceCurrency is USD or item is a wishlist item, otherwise NIS.
    static func formattedPrice(price: String, priceCurrency: String, isWishlist: Bool) -> String {
        let trimmed = price.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "—" }
        if priceCurrency == "USD" || isWishlist { return "$ \(trimmed)" }
        return priceInNIS(price)
    }

    /// Compare entered (your) price with current store price for trend display. Used for wishlist price coloring and arrow.
    enum PriceTrend {
        case higher   // current > entered (red, arrow up)
        case lower    // current < entered (green, arrow down)
        case same     // equal or unparseable
    }
    static func priceTrend(entered: String, current: String) -> PriceTrend {
        let a = Double(entered.trimmingCharacters(in: .whitespaces))
        let b = Double(current.trimmingCharacters(in: .whitespaces))
        guard let ea = a, let cb = b else { return .same }
        if cb > ea { return .higher }
        if cb < ea { return .lower }
        return .same
    }

    static let columnOrder = [
        "id", "name", "description", "categoryId", "price", "purchaseDate", "condition", "quantity",
        "createdAt", "updatedAt", "photoIds", "webLink", "tags", "locationId", "priceCurrency"
    ]
}
