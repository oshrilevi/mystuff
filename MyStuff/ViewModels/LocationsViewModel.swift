import Foundation
import SwiftUI

@MainActor
final class LocationsViewModel: ObservableObject {
    @Published var locations: [Location] = []
    @Published var defaultLocationId: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sheets: SheetsService
    private var spreadsheetId: String? { appState.spreadsheetId }
    private let appState: AppState

    private let defaultLocationIdKey = "mystuff_default_location_id"

    init(sheets: SheetsService, appState: AppState) {
        self.sheets = sheets
        self.appState = appState
        defaultLocationId = UserDefaults.standard.string(forKey: defaultLocationIdKey)
    }

    func load() async {
        guard let sid = spreadsheetId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let titles = try await sheets.getSheetTitles(spreadsheetId: sid)
            if !titles.contains("Locations") {
                try await sheets.addSheet(spreadsheetId: sid, title: "Locations")
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Locations", values: [["id", "name", "order"]])
            }
            let rows: [[String]] = try await sheets.getValues(spreadsheetId: sid, range: "Locations!A2:Z500")
            let loaded: [Location] = rows.enumerated().compactMap { index, row in
                guard row.count >= 2 else { return nil }
                let order = row.count > 2 ? (Int(row[2]) ?? index + 2) : index + 2
                return Location(id: row[0], name: row[1], order: order)
            }
            locations = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setDefaultLocation(id: String?) {
        defaultLocationId = id
        if let id = id {
            UserDefaults.standard.set(id, forKey: defaultLocationIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultLocationIdKey)
        }
    }

    func addLocation(name: String) async {
        guard let sid = spreadsheetId else { return }
        let location = Location(name: name, order: locations.count)
        let values = [[location.id, location.name, "\(location.order)"]]
        do {
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Locations", values: values)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateLocation(id: String, name: String) async {
        guard let sid = spreadsheetId else { return }
        guard let index = locations.firstIndex(where: { $0.id == id }) else { return }
        var updated = locations
        updated[index].name = name
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Locations")
            let header = [["id", "name", "order"]]
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Locations", values: header)
            let rows = updated.map { [$0.id, $0.name, "\($0.order)"] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Locations", values: rows)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteLocation(ids: [String]) async {
        guard let sid = spreadsheetId else { return }
        let idSet = Set(ids)
        var updated = locations.filter { !idSet.contains($0.id) }
        if let currentDefault = defaultLocationId, idSet.contains(currentDefault) {
            setDefaultLocation(id: nil)
        }
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Locations")
            let header = [["id", "name", "order"]]
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Locations", values: header)
            let rows = updated.map { [$0.id, $0.name, "\($0.order)"] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Locations", values: rows)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
