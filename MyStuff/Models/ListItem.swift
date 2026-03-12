import Foundation

struct ListItem: Identifiable, Equatable {
    let id: String
    var listId: String
    var itemId: String
    /// Sort order of this item within its list.
    var order: Int
    /// Optional per-item-in-list note (e.g. \"bring only if cold\").
    var note: String

    init(
        id: String = UUID().uuidString,
        listId: String,
        itemId: String,
        order: Int = 0,
        note: String = ""
    ) {
        self.id = id
        self.listId = listId
        self.itemId = itemId
        self.order = order
        self.note = note
    }

    static let columnOrder = ["id", "listId", "itemId", "order", "note"]
}

