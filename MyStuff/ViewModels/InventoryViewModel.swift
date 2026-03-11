import Foundation
import SwiftUI

@MainActor
final class InventoryViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var categories: [Category] = []
    @Published var searchText = ""
    @Published var selectedCategoryId: String?
    /// Last purchase date used when adding a new item; used as default when opening the add form.
    @Published var lastNewItemPurchaseDate: Date?
    /// Last category used when adding a new item; used as default when opening the add form.
    @Published var lastNewItemCategoryId: String?
    /// Last location used when adding a new item; used as default when opening the add form.
    @Published var lastNewItemLocationId: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Category section IDs that are collapsed in Items/Gallery; persists across tab switches.
    @Published var categorySectionCollapsedIds: Set<String> = [] {
        didSet {
            saveCategorySectionCollapsedIds()
        }
    }
    /// When true, initial "all collapsed" has been applied once; avoids overwriting user's expand/collapse.
    @Published var hasAppliedInitialCategoryCollapse = false

    private let sheets: SheetsService
    private let drive: DriveService
    private var spreadsheetId: String? { appState.spreadsheetId }
    private var driveFolderId: String? { appState.driveFolderId }
    private let appState: AppState
    private weak var attachments: AttachmentsViewModel?
    private let itemsCacheKey = "mystuff_items_cache"
    private let categorySectionCollapsedIdsKey = "mystuff_category_section_collapsed_ids"

    init(sheets: SheetsService, drive: DriveService, appState: AppState, attachments: AttachmentsViewModel? = nil) {
        self.sheets = sheets
        self.drive = drive
        self.appState = appState
        self.attachments = attachments
        if let data = UserDefaults.standard.data(forKey: categorySectionCollapsedIdsKey),
           let ids = try? JSONDecoder().decode(Set<String>.self, from: data) {
            categorySectionCollapsedIds = ids
            hasAppliedInitialCategoryCollapse = true
        }
    }

    var filteredItems: [Item] {
        var list = items
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q)
                    || $0.description.lowercased().contains(q)
                    || $0.tags.contains { $0.lowercased().contains(q) }
            }
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
        } catch let error as SheetsError {
            switch error {
            case .unauthorized:
                errorMessage = "Your Google session expired. Please sign out and sign in again."
            default:
                errorMessage = error.localizedDescription
            }
        } catch let error as DriveError {
            switch error {
            case .unauthorized:
                errorMessage = "Your Google session expired. Please sign out and sign in again."
            default:
                errorMessage = error.localizedDescription
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
        } catch let error as SheetsError {
            switch error {
            case .unauthorized:
                errorMessage = "Your Google session expired. Please sign out and sign in again."
            default:
                errorMessage = error.localizedDescription
            }
        } catch let error as DriveError {
            switch error {
            case .unauthorized:
                errorMessage = "Your Google session expired. Please sign out and sign in again."
            default:
                errorMessage = error.localizedDescription
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
        var photoIds: [String] = item.photoIds
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
        } catch let error as SheetsError {
            switch error {
            case .unauthorized:
                errorMessage = "Your Google session expired. Please sign out and sign in again."
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateItem(_ item: Item, newImageData: [Data] = [], replaceExistingPhotos: Bool = false) async {
        guard let sid = spreadsheetId, let fid = driveFolderId else { return }
        var photoIds: [String] = replaceExistingPhotos ? [] : item.photoIds
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

    func deleteItems(ids: [String]) async {
        guard let sid = spreadsheetId else { return }
        let idSet = Set(ids)
        let updated = items.filter { !idSet.contains($0.id) }
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Items")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Items", values: [Item.columnOrder])
            if !updated.isEmpty {
                let rows = updated.map { itemToRow($0) }
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Items", values: rows)
            }
            await attachments?.removeAttachments(forItemIds: idSet)
            await loadItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func thumbnailURL(for item: Item) -> URL? {
        guard let first = item.photoIds.first else { return nil }
        return drive.thumbnailURL(fileId: first)
    }

    private func saveCategorySectionCollapsedIds() {
        if let data = try? JSONEncoder().encode(categorySectionCollapsedIds) {
            UserDefaults.standard.set(data, forKey: categorySectionCollapsedIdsKey)
        }
    }

    private func itemToRow(_ item: Item) -> [String] {
        [
            item.id, item.name, item.description, item.categoryId,
            item.price, item.purchaseDate, item.condition, String(item.quantity),
            item.createdAt, item.updatedAt,
            item.photoIds.joined(separator: ","),
            item.webLink,
            item.tags.joined(separator: ","),
            item.locationId,
            item.priceCurrency
        ]
    }

    private func parseItemRow(_ row: [String]) -> Item? {
        // Sheets API may omit trailing empty cells. Support both old (10 cols) and new (11 cols with quantity).
        guard row.count >= 9 else { return nil }
        let quantity: Int
        let createdAt: String
        let updatedAt: String
        let photoIds: [String]
        if row.count >= 11 {
            quantity = Int(row[7].trimmingCharacters(in: .whitespaces)) ?? 1
            createdAt = row.count > 8 ? row[8] : ""
            updatedAt = row.count > 9 ? row[9] : ""
            photoIds = row.count > 10 && !row[10].isEmpty ? row[10].split(separator: ",").map(String.init) : []
        } else {
            quantity = 1
            createdAt = row.count > 7 ? row[7] : ""
            updatedAt = row.count > 8 ? row[8] : ""
            photoIds = row.count > 9 && !row[9].isEmpty ? row[9].split(separator: ",").map(String.init) : []
        }
        let webLink = row.count > 11 ? row[11] : ""
        let tags: [String] = row.count > 12 && !row[12].isEmpty
            ? row[12].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            : []
        let locationId = row.count > 13 ? row[13] : ""
        let priceCurrency = row.count > 14 ? row[14] : ""
        return Item(
            id: row[0],
            name: row.count > 1 ? row[1] : "",
            description: row.count > 2 ? row[2] : "",
            categoryId: row.count > 3 ? row[3] : "",
            price: row.count > 4 ? row[4] : "",
            purchaseDate: row.count > 5 ? row[5] : "",
            condition: row.count > 6 ? row[6] : "",
            quantity: max(1, quantity),
            createdAt: createdAt,
            updatedAt: updatedAt,
            photoIds: photoIds,
            webLink: webLink,
            tags: tags,
            locationId: locationId,
            priceCurrency: priceCurrency
        )
    }

    private func parseCategoryRow(_ row: [String], rowIndex: Int) -> Category? {
        guard row.count >= 2 else { return nil }
        let order = row.count > 2 ? (Int(row[2]) ?? rowIndex) : rowIndex
        let color = row.count > 3 && !row[3].isEmpty ? row[3] : nil
        let parentId = row.count > 4 && !row[4].isEmpty ? row[4] : nil
        return Category(id: row[0], name: row[1], order: order, color: color, parentId: parentId)
    }
}
