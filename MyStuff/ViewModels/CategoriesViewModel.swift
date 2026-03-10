import Foundation
import SwiftUI

@MainActor
final class CategoriesViewModel: ObservableObject {
    @Published var categories: [Category] = []
    @Published var pinnedCategoryIds: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// ID of the category named "Wishlist", if present. Used as default when adding an item from the store browser.
    var wishlistCategoryId: String? { categories.first(where: { Category.isWishlist($0.name) })?.id }

    private let sheets: SheetsService
    private var spreadsheetId: String? { appState.spreadsheetId }
    private let appState: AppState

    private let categoriesCacheKey = "mystuff_categories_cache"
    private let pinnedCategoryIdsKey = "mystuff_pinned_category_ids"

    init(sheets: SheetsService, appState: AppState) {
        self.sheets = sheets
        self.appState = appState
        if let data = UserDefaults.standard.data(forKey: pinnedCategoryIdsKey),
           let ids = try? JSONDecoder().decode(Set<String>.self, from: data) {
            pinnedCategoryIds = ids
        }
    }

    func togglePinned(categoryId: String) {
        if pinnedCategoryIds.contains(categoryId) {
            pinnedCategoryIds.remove(categoryId)
        } else {
            pinnedCategoryIds.insert(categoryId)
        }
        if let data = try? JSONEncoder().encode(pinnedCategoryIds) {
            UserDefaults.standard.set(data, forKey: pinnedCategoryIdsKey)
        }
    }

    func load() async {
        guard let sid = spreadsheetId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let rows: [[String]] = try await sheets.getValues(spreadsheetId: sid, range: "Categories!A2:Z500")
            let loaded: [Category] = rows.enumerated().compactMap { index, row in
                guard row.count >= 2 else { return nil }
                let order = row.count > 2 ? (Int(row[2]) ?? index + 2) : index + 2
                let color = row.count > 3 && !row[3].isEmpty ? row[3] : nil
                return Category(id: row[0], name: row[1], order: order, color: color)
            }
            categories = loaded
            if let data = try? JSONEncoder().encode(loaded.map { [$0.id, $0.name, "\($0.order)", $0.color ?? ""] }) {
                UserDefaults.standard.set(data, forKey: categoriesCacheKey)
            }
            applyWishlistPinnedByDefault()
        } catch {
            errorMessage = error.localizedDescription
            if let data = UserDefaults.standard.data(forKey: categoriesCacheKey),
               let rows = try? JSONDecoder().decode([[String]].self, from: data) {
                let cached: [Category] = rows.enumerated().compactMap { index, row in
                    guard row.count >= 2 else { return nil }
                    let order = row.count > 2 ? (Int(row[2]) ?? index + 2) : index + 2
                    let color = row.count > 3 && !row[3].isEmpty ? row[3] : nil
                    return Category(id: row[0], name: row[1], order: order, color: color)
                }
                categories = cached
                applyWishlistPinnedByDefault()
            }
        }
    }

    /// If the user has never set pinned categories, pin the Wishlist category by default.
    private func applyWishlistPinnedByDefault() {
        guard UserDefaults.standard.object(forKey: pinnedCategoryIdsKey) == nil else { return }
        guard let wishlist = categories.first(where: { Category.isWishlist($0.name) }) else { return }
        pinnedCategoryIds.insert(wishlist.id)
        if let data = try? JSONEncoder().encode(pinnedCategoryIds) {
            UserDefaults.standard.set(data, forKey: pinnedCategoryIdsKey)
        }
    }

    func addCategory(name: String, color: String? = nil) async {
        guard let sid = spreadsheetId else { return }
        let category = Category(name: name, order: categories.count, color: color)
        let values = [[category.id, category.name, "\(category.order)", category.color ?? ""]]
        do {
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: values)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateCategory(id: String, name: String, color: String? = nil) async {
        guard let sid = spreadsheetId else { return }
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        var updated = categories
        updated[index].name = name
        updated[index].color = color
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Categories")
            let header = [["id", "name", "order", "color"]]
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: header)
            let rows = updated.map { [$0.id, $0.name, "\($0.order)", $0.color ?? ""] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: rows)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCategory(ids: [String]) async {
        guard let sid = spreadsheetId else { return }
        let idSet = Set(ids)
        var updated = categories.filter { !idSet.contains($0.id) }
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Categories")
            let header = [["id", "name", "order", "color"]]
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: header)
            let rows = updated.map { [$0.id, $0.name, "\($0.order)", $0.color ?? ""] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: rows)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Updates category order from a reordered list; persists to Sheets and cache.
    func reorderCategories(to newOrder: [Category]) async {
        guard let sid = spreadsheetId else { return }
        let reordered: [Category] = newOrder.enumerated().map { index, cat in
            var c = cat
            c.order = index
            return c
        }
        categories = reordered
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Categories")
            let header = [["id", "name", "order", "color"]]
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: header)
            let rows = reordered.map { [$0.id, $0.name, "\($0.order)", $0.color ?? ""] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: rows)
            }
            if let data = try? JSONEncoder().encode(reordered.map { [$0.id, $0.name, "\($0.order)", $0.color ?? ""] }) {
                UserDefaults.standard.set(data, forKey: categoriesCacheKey)
            }
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }
}
