import Foundation
import SwiftUI

@MainActor
final class WishlistViewModel: ObservableObject {
    @Published var items: [WishlistItem] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sheets: SheetsService
    private let drive: DriveService
    private var spreadsheetId: String? { appState.spreadsheetId }
    private var driveFolderId: String? { appState.driveFolderId }
    private let appState: AppState
    private let cacheKey = "mystuff_wishlist_cache"

    init(sheets: SheetsService, drive: DriveService, appState: AppState) {
        self.sheets = sheets
        self.drive = drive
        self.appState = appState
    }

    var filteredItems: [WishlistItem] {
        guard !searchText.isEmpty else { return items }
        let q = searchText.lowercased()
        return items.filter {
            $0.name.lowercased().contains(q)
                || $0.notes.lowercased().contains(q)
                || $0.link.lowercased().contains(q)
        }
    }

    func load() async {
        guard let sid = spreadsheetId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // Ensure Wishlist sheet exists (adds it for existing spreadsheets that don't have it yet)
            try await sheets.ensureWishlistSheetExists(spreadsheetId: sid)
            // Use A:Z so empty sheet (header only) returns one row; skip header when parsing
            let allRows = try await sheets.getValues(spreadsheetId: sid, range: "Wishlist!A:Z")
            let dataRows = allRows.isEmpty ? [] : Array(allRows.dropFirst())
            let loaded = dataRows.compactMap { parseRow($0) }
            items = loaded
            if let data = try? JSONEncoder().encode(loaded.map { itemToRow($0) }) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
        } catch {
            errorMessage = error.localizedDescription
            if let data = UserDefaults.standard.data(forKey: cacheKey),
               let rows = try? JSONDecoder().decode([[String]].self, from: data) {
                items = rows.compactMap { parseRow($0) }
            }
        }
    }

    func add(_ item: WishlistItem, imageData: Data? = nil) async {
        guard let sid = spreadsheetId else {
            errorMessage = "Not bootstrapped"
            return
        }
        var newItem = item
        if let data = imageData, let fid = driveFolderId {
            let name = "wishlist_\(item.id).jpg"
            if let fileId = try? await drive.uploadImage(data: data, mimeType: "image/jpeg", filename: name, parentFolderId: fid) {
                newItem.photoId = fileId
            }
        }
        let values = [itemToRow(newItem)]
        do {
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Wishlist", values: values)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func update(_ item: WishlistItem, imageData: Data? = nil, removePhoto: Bool = false) async {
        guard let sid = spreadsheetId else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        if removePhoto {
            updated.photoId = ""
        } else if let data = imageData, let fid = driveFolderId {
            let name = "wishlist_\(item.id)_\(UUID().uuidString.prefix(8)).jpg"
            if let fileId = try? await drive.uploadImage(data: data, mimeType: "image/jpeg", filename: name, parentFolderId: fid) {
                updated.photoId = fileId
            }
        }
        let rowIndex = index + 1
        do {
            try await sheets.updateRow(spreadsheetId: sid, sheetName: "Wishlist", rowIndex: rowIndex, values: itemToRow(updated))
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(ids: [String]) async {
        guard let sid = spreadsheetId else { return }
        let idSet = Set(ids)
        let updated = items.filter { !idSet.contains($0.id) }
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Wishlist")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Wishlist", values: [WishlistItem.columnOrder])
            if !updated.isEmpty {
                let rows = updated.map { itemToRow($0) }
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Wishlist", values: rows)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func itemToRow(_ item: WishlistItem) -> [String] {
        [item.id, item.name, item.notes, item.price, item.link, item.createdAt, item.photoId]
    }

    private func parseRow(_ row: [String]) -> WishlistItem? {
        guard row.count >= 2 else { return nil }
        let createdAt = row.count > 5 ? row[5] : ISO8601DateFormatter().string(from: Date())
        let photoId = row.count > 6 ? row[6] : ""
        return WishlistItem(
            id: row[0],
            name: row.count > 1 ? row[1] : "",
            notes: row.count > 2 ? row[2] : "",
            price: row.count > 3 ? row[3] : "",
            link: row.count > 4 ? row[4] : "",
            createdAt: createdAt,
            photoId: photoId
        )
    }
}
