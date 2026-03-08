import Foundation

struct Location: Identifiable, Equatable {
    let id: String
    var name: String
    var order: Int

    init(id: String = UUID().uuidString, name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }

    static let columnOrder = ["id", "name", "order"]
}
