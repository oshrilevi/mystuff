import Foundation

struct Item: Identifiable, Equatable {
    let id: String
    var name: String
    var description: String
    var categoryId: String
    var price: String
    var purchaseDate: String // ISO8601 or YYYY-MM-DD
    var condition: String
    var createdAt: String
    var updatedAt: String
    var photoIds: [String] // Drive file IDs

    init(
        id: String = UUID().uuidString,
        name: String = "",
        description: String = "",
        categoryId: String = "",
        price: String = "",
        purchaseDate: String = "",
        condition: String = "",
        createdAt: String = "",
        updatedAt: String = "",
        photoIds: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.categoryId = categoryId
        self.price = price
        self.purchaseDate = purchaseDate
        self.condition = condition
        self.createdAt = createdAt.isEmpty ? ISO8601DateFormatter().string(from: Date()) : createdAt
        self.updatedAt = updatedAt.isEmpty ? ISO8601DateFormatter().string(from: Date()) : updatedAt
        self.photoIds = photoIds
    }

    static let conditionPresets = ["New", "Like new", "Good", "Fair", "Poor"]

    static let columnOrder = [
        "id", "name", "description", "categoryId", "price", "purchaseDate", "condition",
        "createdAt", "updatedAt", "photoIds"
    ]
}
