import Foundation

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
}
