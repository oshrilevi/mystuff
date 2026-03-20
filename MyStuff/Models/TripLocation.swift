import Foundation

struct TripLocation: Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var description: String
    var tags: [String]
    var latitude: Double?
    var longitude: Double?
    var createdAt: String
    var updatedAt: String

    static let columnOrder = ["id", "name", "description", "tags", "latitude", "longitude", "createdAt", "updatedAt"]

    var coordinate: (latitude: Double, longitude: Double)? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return (lat, lon)
    }
}
