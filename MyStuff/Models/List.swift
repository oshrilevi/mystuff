import Foundation

struct UserList: Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    /// Optional freeform notes for this list (e.g. goals, constraints).
    var notes: String
    /// Sort order; row-based in the sheet.
    var order: Int
    var createdAt: String
    var updatedAt: String

    init(
        id: String = UUID().uuidString,
        name: String,
        notes: String = "",
        order: Int = 0,
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.order = order
        let now = ISO8601DateFormatter().string(from: Date())
        self.createdAt = createdAt.isEmpty ? now : createdAt
        self.updatedAt = updatedAt.isEmpty ? now : updatedAt
    }

    static let columnOrder = ["id", "name", "notes", "order", "createdAt", "updatedAt"]
}

