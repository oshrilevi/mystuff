import Foundation

struct Trip: Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var description: String
    var tags: [String]
    var locationIds: [String]
    var order: Int
    var createdAt: String
    var updatedAt: String

    static let columnOrder = ["id", "name", "description", "tags", "locationIds", "order", "createdAt", "updatedAt"]
}
