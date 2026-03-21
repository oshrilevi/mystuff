import Foundation

// MARK: - VisitSighting

struct VisitSighting: Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var wikiDescription: String
    var imageURL: String  // absolute URL string; empty if unknown
    var wikiURL: String   // Wikipedia page URL; empty if unknown

    init(id: String = UUID().uuidString, name: String, wikiDescription: String = "", imageURL: String = "", wikiURL: String = "") {
        self.id = id
        self.name = name
        self.wikiDescription = wikiDescription
        self.imageURL = imageURL
        self.wikiURL = wikiURL
    }
}

extension VisitSighting: Codable {
    enum CodingKeys: String, CodingKey { case id, name, wikiDescription, imageURL, wikiURL }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        name            = try c.decode(String.self, forKey: .name)
        wikiDescription = (try? c.decode(String.self, forKey: .wikiDescription)) ?? ""
        imageURL        = (try? c.decode(String.self, forKey: .imageURL)) ?? ""
        wikiURL         = (try? c.decode(String.self, forKey: .wikiURL)) ?? ""
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

    var hebrewLabel: String {
        switch self {
        case .dawn:      return "שחר"
        case .morning:   return "בוקר"
        case .midday:    return "צהריים"
        case .afternoon: return "אחה\"צ"
        case .dusk:      return "דמדומים"
        case .night:     return "לילה"
        }
    }
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
    var photoIds: [String]

    // v1 (8 cols):  id, tripId, locationId, date, summary, tags, createdAt, updatedAt
    // v2 (11 cols): id, tripId, name, description, latitude, longitude, date, time, tags, createdAt, updatedAt
    // v3 (10 cols): id, tripId, sightings(JSON), latitude, longitude, date, timeOfDay, tags, createdAt, updatedAt
    static let columnOrder = ["id", "tripId", "sightings", "latitude", "longitude", "date", "timeOfDay", "tags", "createdAt", "updatedAt", "photos"]

    init(id: String = UUID().uuidString, tripId: String, sightings: [VisitSighting] = [],
         latitude: Double? = nil, longitude: Double? = nil, date: String, timeOfDay: String = "",
         tags: [String] = [], createdAt: String = "", updatedAt: String = "", photoIds: [String] = []) {
        self.id = id
        self.tripId = tripId
        self.sightings = sightings
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
        self.timeOfDay = timeOfDay
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.photoIds = photoIds
    }
}
