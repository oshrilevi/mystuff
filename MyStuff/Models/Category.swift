import Foundation

struct Category: Identifiable, Equatable {
    let id: String
    var name: String
    var order: Int
    /// Optional parent category id. When set, this category is treated as a subcategory of the parent.
    var parentId: String?
    /// SF Symbol name for a predefined icon; used when iconFileId is nil.
    var iconSymbol: String?
    /// Drive file ID for a custom category icon image; takes precedence over iconSymbol when set.
    var iconFileId: String?

    init(id: String = UUID().uuidString, name: String, order: Int = 0, parentId: String? = nil, iconSymbol: String? = nil, iconFileId: String? = nil) {
        self.id = id
        self.name = name
        self.order = order
        self.parentId = parentId
        self.iconSymbol = iconSymbol
        self.iconFileId = iconFileId
    }

    static let columnOrder = ["id", "name", "order", "parentId", "iconSymbol", "iconFileId"]

    /// True when the category name is "Wishlist" (case-insensitive). Used to hide totals, date sort, and quantity/purchase date in UI.
    static func isWishlist(_ name: String) -> Bool {
        name.caseInsensitiveCompare("Wishlist") == .orderedSame
    }

    /// Predefined SF Symbol names for category icon picker.
    static let predefinedIconSymbols: [String] = [
        "folder", "folder.fill", "tag", "tag.fill", "star", "star.fill",
        "heart", "heart.fill", "book", "book.fill", "book.closed",
        "camera", "camera.fill", "gamecontroller", "gamecontroller.fill",
        "car", "car.fill", "house", "house.fill", "gift", "gift.fill",
        "laptopcomputer", "desktopcomputer", "tv", "smartphone",
        "wrench.and.screwdriver", "paintbrush", "paintbrush.fill",
        "leaf", "leaf.fill", "drop", "drop.fill", "flame", "flame.fill",
        "cart", "cart.fill", "creditcard", "creditcard.fill",
        "doc", "doc.fill", "archivebox", "archivebox.fill"
    ]
}
