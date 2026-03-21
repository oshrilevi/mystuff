import Foundation
import MapKit

// MARK: - Observation Model

struct iNaturalistObservation: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    let taxonName: String
    let commonName: String?
    let observedOn: String?
    let photoURL: URL?
    let qualityGrade: String
    let observerLogin: String?
    let observationURL: URL?
    let wikiURL: URL?

    var displayName: String {
        commonName ?? taxonName
    }
}

// MARK: - Taxon Filter

enum InatTaxonFilter: String, CaseIterable, Identifiable {
    case all
    case birds
    case mammals

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:     return "Vertebrates"
        case .birds:   return "Birds"
        case .mammals: return "Mammals"
        }
    }

    // iNaturalist taxon IDs: https://www.inaturalist.org/taxa
    var taxonId: Int? {
        switch self {
        case .all:     return 355675   // Vertebrata (excludes insects, plants, fungi, etc.)
        case .birds:   return 3       // Aves
        case .mammals: return 40151   // Mammalia
        }
    }
}

// MARK: - INaturalistService

enum INaturalistService {
    /// Fetches the best available photo URL for a species name from iNaturalist.
    /// Returns nil if no taxon is found or no photo is available.
    static func fetchPhotoURL(name: String) async -> URL? {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        guard let url = URL(string: "https://api.inaturalist.org/v1/taxa?q=\(encoded)&limit=1") else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let photo = first["default_photo"] as? [String: Any],
              let urlString = photo["medium_url"] as? String ?? photo["square_url"] as? String
        else { return nil }
        return URL(string: urlString)
    }

    /// Fetches research-grade observations within the given map region.
    static func fetchObservations(
        in region: MKCoordinateRegion,
        taxonFilter: InatTaxonFilter
    ) async throws -> [iNaturalistObservation] {
        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        let swLat   = region.center.latitude  - halfLat
        let swLng   = region.center.longitude - halfLon
        let neLat   = region.center.latitude  + halfLat
        let neLng   = region.center.longitude + halfLon

        var components = URLComponents(string: "https://api.inaturalist.org/v1/observations")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "swlat",         value: "\(swLat)"),
            URLQueryItem(name: "swlng",         value: "\(swLng)"),
            URLQueryItem(name: "nelat",         value: "\(neLat)"),
            URLQueryItem(name: "nelng",         value: "\(neLng)"),
            URLQueryItem(name: "quality_grade", value: "research"),
            URLQueryItem(name: "locale",        value: "he"),
            URLQueryItem(name: "per_page",      value: "100"),
            URLQueryItem(name: "order_by",      value: "observed_on"),
            URLQueryItem(name: "order",         value: "desc"),
        ]
        if let taxonId = taxonFilter.taxonId {
            items.append(URLQueryItem(name: "taxon_id", value: "\(taxonId)"))
        }
        components.queryItems = items

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response  = try JSONDecoder().decode(InatObsResponse.self, from: data)

        return response.results.compactMap { raw in
            // iNat returns coordinates as "lat,lng" in the `location` field.
            guard
                let location = raw.location,
                case let parts = location.split(separator: ","),
                parts.count == 2,
                let lat = Double(parts[0]),
                let lng = Double(parts[1])
            else { return nil }

            // iNat photo URLs are square (75px); replace with medium for better display.
            let photoURL: URL? = raw.photos?.first?.url.flatMap {
                URL(string: $0.replacingOccurrences(of: "/square.", with: "/medium."))
            }

            return iNaturalistObservation(
                id:             raw.id,
                coordinate:     CLLocationCoordinate2D(latitude: lat, longitude: lng),
                taxonName:      raw.taxon?.name ?? "Unknown",
                commonName:     raw.taxon?.preferred_common_name,
                observedOn:     raw.observed_on,
                photoURL:       photoURL,
                qualityGrade:   raw.quality_grade ?? "needs_id",
                observerLogin:  raw.user?.login,
                observationURL: raw.uri.flatMap { URL(string: $0) },
                wikiURL:        {
                    let searchTerm = raw.taxon?.preferred_common_name ?? raw.taxon?.name ?? ""
                    guard !searchTerm.isEmpty,
                          var comps = URLComponents(string: "https://he.wikipedia.org/w/index.php")
                    else { return nil }
                    comps.queryItems = [URLQueryItem(name: "search", value: searchTerm)]
                    return comps.url
                }()
            )
        }
    }
}

// MARK: - Private Decodable types

private struct InatObsResponse: Decodable {
    let results: [InatRawObservation]
}

private struct InatRawObservation: Decodable {
    let id: Int
    let location: String?   // "lat,lng" e.g. "32.0566,34.8211"
    let quality_grade: String?
    let observed_on: String?
    let taxon: InatRawTaxon?
    let photos: [InatRawPhoto]?
    let user: InatRawUser?
    let uri: String?
}

private struct InatRawTaxon: Decodable {
    let name: String?
    let preferred_common_name: String?
}

private struct InatRawPhoto: Decodable {
    let url: String?
}

private struct InatRawUser: Decodable {
    let login: String?
}
