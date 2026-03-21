import Foundation
import SwiftUI

// MARK: - Location Type

enum LocationType: String, CaseIterable, Codable, Hashable {
    case fishPonds       = "Fish Ponds"
    case natureReserve   = "Nature Reserve"
    case photoSpot       = "Photo Spot"
    case scenicViewpoint = "Scenic Viewpoint"
    case trail           = "Trail"
    case waterReservoir  = "Water Reservoir"

    /// Ascending display order matches raw value alphabetical order.
    static var sorted: [LocationType] { allCases.sorted { $0.rawValue < $1.rawValue } }

    var color: Color {
        switch self {
        case .fishPonds:       return .teal
        case .natureReserve:   return .green
        case .photoSpot:       return .purple
        case .scenicViewpoint: return .orange
        case .trail:           return Color(red: 0.6, green: 0.4, blue: 0.2) // brown
        case .waterReservoir:  return .blue
        }
    }

    var systemImage: String {
        switch self {
        case .fishPonds:       return "fish.fill"
        case .natureReserve:   return "leaf.fill"
        case .photoSpot:       return "camera.fill"
        case .scenicViewpoint: return "binoculars.fill"
        case .trail:           return "figure.hiking"
        case .waterReservoir:  return "drop.fill"
        }
    }
}

// MARK: - Model

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
    var type: LocationType

    // New columns always appended for backwards compatibility
    static let columnOrder = ["id", "name", "description", "tags", "latitude", "longitude", "createdAt", "updatedAt", "wikiURL", "type"]

    var coordinate: (latitude: Double, longitude: Double)? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return (lat, lon)
    }
}
