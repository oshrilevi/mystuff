import Foundation

// MARK: - VisitSighting

struct VisitSighting: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var wikiDescription: String

    init(id: String = UUID().uuidString, name: String, wikiDescription: String = "") {
        self.id = id
        self.name = name
        self.wikiDescription = wikiDescription
    }
}

// MARK: - TimeOfDay

enum TimeOfDay: String, CaseIterable, Identifiable {
    case dawn      = "Dawn"
    case morning   = "Morning"
    case midday    = "Midday"
    case afternoon = "Afternoon"
    case dusk      = "Dusk"
    case night     = "Night"

    var id: String { rawValue }
}

// MARK: - TripVisit

struct TripVisit: Identifiable, Equatable, Hashable {
    let id: String
    var tripId: String
    var sightings: [VisitSighting]
    var latitude: Double?
    var longitude: Double?
    var date: String      // YYYY-MM-DD
    var timeOfDay: String // TimeOfDay rawValue
    var tags: [String]
    var createdAt: String
    var updatedAt: String

    // v1 (8 cols):  id, tripId, locationId, date, summary, tags, createdAt, updatedAt
    // v2 (11 cols): id, tripId, name, description, latitude, longitude, date, time, tags, createdAt, updatedAt
    // v3 (10 cols): id, tripId, sightings(JSON), latitude, longitude, date, timeOfDay, tags, createdAt, updatedAt
    static let columnOrder = ["id", "tripId", "sightings", "latitude", "longitude", "date", "timeOfDay", "tags", "createdAt", "updatedAt"]
}
