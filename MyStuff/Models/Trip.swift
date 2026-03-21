import Foundation

struct Trip: Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var description: String
    var locationIds: [String]
    var order: Int
    var createdAt: String
    var updatedAt: String
    var wikiURL: String
    var latitude: Double?
    var longitude: Double?

    // lat/lon appended at end for backwards compatibility with existing sheets
    static let columnOrder = ["id", "name", "description", "tags", "locationIds", "order", "createdAt", "updatedAt", "wikiURL", "latitude", "longitude"]
}
