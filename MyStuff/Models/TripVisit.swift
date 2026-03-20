import Foundation

struct TripVisit: Identifiable, Equatable, Hashable {
    let id: String
    var tripId: String
    var locationId: String
    var date: String
    var summary: String
    var tags: [String]
    var createdAt: String
    var updatedAt: String

    static let columnOrder = ["id", "tripId", "locationId", "date", "summary", "tags", "createdAt", "updatedAt"]
}
