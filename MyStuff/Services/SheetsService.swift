import Foundation

final class SheetsService {
    private let baseURL = "https://sheets.googleapis.com/v4/spreadsheets"
    private let tokenProvider: () async throws -> String

    init(tokenProvider: @escaping () async throws -> String) {
        self.tokenProvider = tokenProvider
    }

    func createSpreadsheet(title: String) async throws -> (id: String, spreadsheetURL: String) {
        let token = try await tokenProvider()
        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "properties": ["title": title],
            "sheets": [
                ["properties": ["title": "Categories"]],
                ["properties": ["title": "Items"]],
                ["properties": ["title": "Wishlist"]]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SheetsError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["spreadsheetId"] as? String else { throw SheetsError.invalidResponse }
        try await appendRows(spreadsheetId: id, sheetName: "Categories", values: [["id", "name", "order"]])
        try await appendRows(spreadsheetId: id, sheetName: "Items", values: [[
            "id", "name", "description", "categoryId", "price", "purchaseDate", "condition", "quantity",
            "createdAt", "updatedAt", "photoIds", "webLink", "tags"
        ]])
        try await appendRows(spreadsheetId: id, sheetName: "Wishlist", values: [WishlistItem.columnOrder])
        return (id, "https://docs.google.com/spreadsheets/d/\(id)")
    }

    func appendRows(spreadsheetId: String, sheetName: String, values: [[String]]) async throws {
        let token = try await tokenProvider()
        let range = "\(sheetName)!A:Z"
        let url = URL(string: "\(baseURL)/\(spreadsheetId)/values/\(range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!):append?valueInputOption=USER_ENTERED")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["values": values]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SheetsError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown")
        }
    }

    func getValues(spreadsheetId: String, range: String) async throws -> [[String]] {
        let token = try await tokenProvider()
        let encoded = range.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? range
        let url = URL(string: "\(baseURL)/\(spreadsheetId)/values/\(encoded)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SheetsError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let values = json?["values"] as? [[Any]] else { return [] }
        return values.map { row in
            (row as? [String]).map { $0 } ?? (row as [Any]).map { "\($0)" }
        }
    }

    func updateRow(spreadsheetId: String, sheetName: String, rowIndex: Int, values: [String]) async throws {
        let token = try await tokenProvider()
        let range = "\(sheetName)!A\(rowIndex + 1):Z\(rowIndex + 1)"
        let url = URL(string: "\(baseURL)/\(spreadsheetId)/values/\(range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)?valueInputOption=USER_ENTERED")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["values": [values]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SheetsError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown")
        }
    }

    func clearSheet(spreadsheetId: String, sheetName: String) async throws {
        let token = try await tokenProvider()
        let range = "\(sheetName)!A:Z"
        let url = URL(string: "\(baseURL)/\(spreadsheetId)/values/\(range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!):clear")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SheetsError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown")
        }
    }

    /// Returns sheet titles (e.g. ["Categories", "Items", "Wishlist"]).
    func getSheetTitles(spreadsheetId: String) async throws -> [String] {
        let token = try await tokenProvider()
        let url = URL(string: "\(baseURL)/\(spreadsheetId)?fields=sheets(properties(title))")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SheetsError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let sheets = json?["sheets"] as? [[String: Any]] else { return [] }
        return sheets.compactMap { sheet -> String? in
            (sheet["properties"] as? [String: Any])?["title"] as? String
        }
    }

    /// Adds a sheet named "Wishlist" if missing, then appends the header row if the sheet is new/empty.
    func ensureWishlistSheetExists(spreadsheetId: String) async throws {
        let titles = try await getSheetTitles(spreadsheetId: spreadsheetId)
        guard !titles.contains("Wishlist") else { return }
        let token = try await tokenProvider()
        let batchURL = URL(string: "\(baseURL)/\(spreadsheetId):batchUpdate")!
        var request = URLRequest(url: batchURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "requests": [
                ["addSheet": ["properties": ["title": "Wishlist"]]]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SheetsError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown")
        }
        try await appendRows(spreadsheetId: spreadsheetId, sheetName: "Wishlist", values: [WishlistItem.columnOrder])
    }
}

enum SheetsError: LocalizedError {
    case requestFailed(String)
    case invalidResponse
    var errorDescription: String? {
        switch self {
        case .requestFailed(let msg): return msg
        case .invalidResponse: return "Invalid response"
        }
    }
}
