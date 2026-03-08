import Foundation
import SwiftUI

@MainActor
final class StoresViewModel: ObservableObject {
    @Published var stores: [UserStore] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sheets: SheetsService
    private var spreadsheetId: String? { appState.spreadsheetId }
    private let appState: AppState

    init(sheets: SheetsService, appState: AppState) {
        self.sheets = sheets
        self.appState = appState
    }

    func load() async {
        guard let sid = spreadsheetId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let titles = try await sheets.getSheetTitles(spreadsheetId: sid)
            if !titles.contains("Stores") {
                try await sheets.addSheet(spreadsheetId: sid, title: "Stores")
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Stores", values: [UserStore.columnOrder])
            }
            let rows: [[String]] = try await sheets.getValues(spreadsheetId: sid, range: "Stores!A2:Z500")
            var loaded: [UserStore] = rows.enumerated().compactMap { index, row in
                guard row.count >= 2 else { return nil }
                let order = row.count > 3 ? (Int(row[3]) ?? index + 2) : index + 2
                let systemImage = row.count > 4 && !row[4].isEmpty ? row[4] : "link"
                let startURL = row.count > 2 ? row[2] : "https://"
                return UserStore(id: row[0], name: row[1], startURL: startURL, order: order, systemImage: systemImage)
            }
            // Seed default stores when sheet exists but has no data (e.g. after migration for existing spreadsheets)
            if loaded.isEmpty {
                let defaultStores: [[String]] = [
                    [UUID().uuidString, "Amazon", "https://www.amazon.com", "0", "cart"],
                    [UUID().uuidString, "AliExpress", "https://www.aliexpress.com/", "1", "bag"],
                    [UUID().uuidString, "B&H Photo", "https://www.bhphotovideo.com/", "2", "camera"]
                ]
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Stores", values: defaultStores)
                loaded = defaultStores.enumerated().map { index, row in
                    UserStore(id: row[0], name: row[1], startURL: row[2], order: index, systemImage: row[4])
                }
            }
            stores = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addStore(name: String, startURL: String, systemImage: String = "link") async {
        guard let sid = spreadsheetId else { return }
        let store = UserStore(name: name, startURL: startURL, order: stores.count, systemImage: systemImage)
        let values = [[store.id, store.name, store.startURL, "\(store.order)", store.systemImage]]
        do {
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Stores", values: values)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateStore(id: String, name: String, startURL: String, systemImage: String) async {
        guard let sid = spreadsheetId else { return }
        guard let index = stores.firstIndex(where: { $0.id == id }) else { return }
        var updated = stores
        updated[index].name = name
        updated[index].startURL = startURL
        updated[index].systemImage = systemImage
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Stores")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Stores", values: [UserStore.columnOrder])
            let rows = updated.map { [$0.id, $0.name, $0.startURL, "\($0.order)", $0.systemImage] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Stores", values: rows)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteStores(ids: [String]) async {
        guard let sid = spreadsheetId else { return }
        let idSet = Set(ids)
        let updated = stores.filter { !idSet.contains($0.id) }
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Stores")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Stores", values: [UserStore.columnOrder])
            let rows = updated.map { [$0.id, $0.name, $0.startURL, "\($0.order)", $0.systemImage] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Stores", values: rows)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
