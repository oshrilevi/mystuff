import Foundation

struct TripLocation: Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var description: String
    var tags: [String]
    var latitude: Double?
    var longitude: Double?
    var wikiURL: String
    var createdAt: String
    var updatedAt: String

    // wikiURL appended at end for backwards compatibility with existing sheets
    static let columnOrder = ["id", "name", "description", "tags", "latitude", "longitude", "createdAt", "updatedAt", "wikiURL"]

    var coordinate: (latitude: Double, longitude: Double)? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return (lat, lon)
    }
}
