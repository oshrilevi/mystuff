import Foundation
import SwiftUI

@MainActor
final class InventoryViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var categories: [Category] = []
    @Published var searchText = ""
    @Published var selectedCategoryId: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sheets: SheetsService
    private let drive: DriveService
    private var spreadsheetId: String? { appState.spreadsheetId }
    private var driveFolderId: String? { appState.driveFolderId }
    private let appState: AppState
    private let itemsCacheKey = "mystuff_items_cache"

    init(sheets: SheetsService, drive: DriveService, appState: AppState) {
        self.sheets = sheets
        self.drive = drive
        self.appState = appState
    }

    var filteredItems: [Item] {
        var list = items
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
            }
        }
        if let cid = selectedCategoryId, !cid.isEmpty {
            list = list.filter { $0.categoryId == cid }
        }
        return list
    }

    func loadItems() async {
        guard let sid = spreadsheetId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let rows = try await sheets.getValues(spreadsheetId: sid, range: "Items!A2:Z1000")
            let loaded = rows.compactMap { row in parseItemRow(row) }
            items = loaded
            if let data = try? JSONEncoder().encode(loaded.map { itemToRow($0) }) {
                UserDefaults.standard.set(data, forKey: itemsCacheKey)
            }
        } catch {
            errorMessage = error.localizedDescription
            if let data = UserDefaults.standard.data(forKey: itemsCacheKey),
               let rows = try? JSONDecoder().decode([[String]].self, from: data) {
                items = rows.compactMap { parseItemRow($0) }
            }
        }
    }

    func loadCategories() async {
        guard let sid = spreadsheetId else { return }
        do {
            let rows = try await sheets.getValues(spreadsheetId: sid, range: "Categories!A2:Z500")
            categories = rows.enumerated().compactMap { index, row in
                parseCategoryRow(row, rowIndex: index + 2)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        await loadCategories()
        await loadItems()
    }

    func addItem(_ item: Item, imageData: [Data] = []) async {
        guard let sid = spreadsheetId, let fid = driveFolderId else {
            errorMessage = "Not bootstrapped"
            return
        }
        var photoIds: [String] = []
        for (i, data) in imageData.enumerated() {
            let mime = "image/jpeg"
            let name = "\(item.id)_\(i).jpg"
            if let id = try? await drive.uploadImage(data: data, mimeType: mime, filename: name, parentFolderId: fid) {
                photoIds.append(id)
            }
        }
        var newItem = item
        newItem.photoIds = photoIds
        let values = itemToRow(newItem)
        do {
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Items", values: [values])
            await loadItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateItem(_ item: Item, newImageData: [Data] = []) async {
        guard let sid = spreadsheetId, let fid = driveFolderId else { return }
        var photoIds = item.photoIds
        for (i, data) in newImageData.enumerated() {
            let name = "\(item.id)_\(UUID().uuidString.prefix(8)).jpg"
            if let id = try? await drive.uploadImage(data: data, mimeType: "image/jpeg", filename: name, parentFolderId: fid) {
                photoIds.append(id)
            }
        }
        var updated = item
        updated.photoIds = photoIds
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let values = itemToRow(updated)
        // updateRow uses 0-based rowIndex; row 0 = header, row 1 = first data
        let rowIndex = index + 1
        do {
            try await sheets.updateRow(spreadsheetId: sid, sheetName: "Items", rowIndex: rowIndex, values: values)
            await loadItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func thumbnailURL(for item: Item) -> URL? {
        guard let first = item.photoIds.first else { return nil }
        return drive.thumbnailURL(fileId: first)
    }

    private func itemToRow(_ item: Item) -> [String] {
        [
            item.id, item.name, item.description, item.categoryId,
            item.price, item.purchaseDate, item.condition,
            item.createdAt, item.updatedAt,
            item.photoIds.joined(separator: ",")
        ]
    }

    private func parseItemRow(_ row: [String]) -> Item? {
        guard row.count >= 10 else { return nil }
        let photoIds = row.count > 9 && !row[9].isEmpty ? row[9].split(separator: ",").map(String.init) : []
        return Item(
            id: row[0],
            name: row.count > 1 ? row[1] : "",
            description: row.count > 2 ? row[2] : "",
            categoryId: row.count > 3 ? row[3] : "",
            price: row.count > 4 ? row[4] : "",
            purchaseDate: row.count > 5 ? row[5] : "",
            condition: row.count > 6 ? row[6] : "",
            createdAt: row.count > 7 ? row[7] : "",
            updatedAt: row.count > 8 ? row[8] : "",
            photoIds: photoIds
        )
    }

    private func parseCategoryRow(_ row: [String], rowIndex: Int) -> Category? {
        guard row.count >= 2 else { return nil }
        let order = row.count > 2 ? (Int(row[2]) ?? rowIndex) : rowIndex
        return Category(id: row[0], name: row[1], order: order)
    }
}
