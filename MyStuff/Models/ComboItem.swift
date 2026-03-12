import Foundation

struct ComboItem: Identifiable, Equatable {
    let id: String
    var comboId: String
    var itemId: String
    /// Sort order of this item within its combo.
    var order: Int

    init(
        id: String = UUID().uuidString,
        comboId: String,
        itemId: String,
        order: Int = 0
    ) {
        self.id = id
        self.comboId = comboId
        self.itemId = itemId
        self.order = order
    }

    static let columnOrder = ["id", "comboId", "itemId", "order"]
}

