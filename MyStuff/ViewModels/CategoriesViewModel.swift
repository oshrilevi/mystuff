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

    /// Top-level categories (no parent), ordered by `order` then name.
    var topLevelCategories: [Category] {
        categories
            .filter { ($0.parentId ?? "").isEmpty }
            .sorted { ($0.order, $0.name.lowercased()) < ($1.order, $1.name.lowercased()) }
    }

    /// Children grouped by parent id, each group ordered by `order` then name.
    var childrenByParentId: [String: [Category]] {
        var result: [String: [Category]] = [:]
        for cat in categories {
            guard let pid = cat.parentId, !pid.isEmpty else { continue }
            result[pid, default: []].append(cat)
        }
        for (pid, list) in result {
            result[pid] = list.sorted { ($0.order, $0.name.lowercased()) < ($1.order, $1.name.lowercased()) }
        }
        return result
    }

    /// Valid parent candidates for a given child (or for a new category when `childId` is nil).
    /// Parents must be top-level, not Wishlist, and not the child itself.
    func validParents(forChildId childId: String? = nil) -> [Category] {
        let child = childId.flatMap { id in categories.first(where: { $0.id == id }) }
        return topLevelCategories.filter { candidate in
            if let child, candidate.id == child.id { return false }
            if Category.isWishlist(candidate.name) { return false }
            return true
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

    /// When row has 4 columns, column 4 may be parentId (new schema) or color (old schema). Use as parentId only if it looks like a UUID.
    static func parentId(from row: [String]) -> String? {
        if row.count > 4 {
            let s = row[4]
            return s.isEmpty ? nil : s
        }
        if row.count > 3 {
            let s = row[3]
            guard !s.isEmpty else { return nil }
            // Old 4-column sheet had id, name, order, color — so column 4 was color. Treat as parentId only if it looks like a UUID.
            if s.contains("-"), s.count == 36, s.allSatisfy({ $0 == "-" || Self.isHexDigit($0) }) { return s }
            if s.hasPrefix("#") || ((s.count == 6 || s.count == 8) && s.allSatisfy { Self.isHexDigit($0) }) { return nil } // hex color
            return s
        }
        return nil
    }

    private static func isHexDigit(_ c: Character) -> Bool {
        (c >= "0" && c <= "9") || (c >= "a" && c <= "f") || (c >= "A" && c <= "F")
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
                let parentId = Self.parentId(from: row)
                return Category(id: row[0], name: row[1], order: order, parentId: parentId)
            }
            categories = loaded
            if let data = try? JSONEncoder().encode(loaded.map { [$0.id, $0.name, "\($0.order)", $0.parentId ?? ""] }) {
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
                    let parentId = Self.parentId(from: row)
                    return Category(id: row[0], name: row[1], order: order, parentId: parentId)
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

    func addCategory(name: String, parentId: String? = nil) async {
        guard let sid = spreadsheetId else { return }
        let category = Category(name: name, order: categories.count, parentId: parentId)
        let values = [[category.id, category.name, "\(category.order)", category.parentId ?? ""]]
        do {
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: values)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateCategory(id: String, name: String, parentId: String? = nil) async {
        guard let sid = spreadsheetId else { return }
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        var updated = categories
        updated[index].name = name
        updated[index].parentId = parentId
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Categories")
            let header = [Category.columnOrder]
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: header)
            let rows = updated.map { [$0.id, $0.name, "\($0.order)", $0.parentId ?? ""] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: rows)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns false when assigning `newParentId` would violate hierarchy rules (depth > 2, Wishlist constraints, etc.).
    private func canSetParent(childId: String, newParentId: String?) -> Bool {
        guard let child = categories.first(where: { $0.id == childId }) else { return false }
        // Keep Wishlist as top-level only; it cannot be a parent or child.
        if Category.isWishlist(child.name) { return false }

        // Clearing parent is always allowed.
        guard let newParentId else { return true }

        if newParentId == childId { return false }
        guard let parent = categories.first(where: { $0.id == newParentId }) else { return false }
        if Category.isWishlist(parent.name) { return false }
        // Parents must be top-level.
        if let parentParentId = parent.parentId, !parentParentId.isEmpty { return false }
        // A category that already has children cannot itself become a child (would create depth 3).
        if let children = childrenByParentId[child.id], !children.isEmpty { return false }
        return true
    }

    /// Assigns or clears a parent for a category, enforcing a maximum depth of 2.
    func setParent(childId: String, parentId: String?) async {
        guard let sid = spreadsheetId else { return }
        guard canSetParent(childId: childId, newParentId: parentId) else { return }
        guard let index = categories.firstIndex(where: { $0.id == childId }) else { return }

        var updated = categories
        updated[index].parentId = parentId
        categories = updated

        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Categories")
            let header = [Category.columnOrder]
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: header)
            let rows = updated.map { [$0.id, $0.name, "\($0.order)", $0.parentId ?? ""] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: rows)
            }
            if let data = try? JSONEncoder().encode(rows) {
                UserDefaults.standard.set(data, forKey: categoriesCacheKey)
            }
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    func deleteCategory(ids: [String]) async {
        guard let sid = spreadsheetId else { return }
        let idSet = Set(ids)
        let updated = categories.filter { !idSet.contains($0.id) }
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Categories")
            let header = [Category.columnOrder]
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: header)
            let rows = updated.map { [$0.id, $0.name, "\($0.order)", $0.parentId ?? ""] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: rows)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Updates category order from a reordered list; persists to Sheets and cache.
    /// `newOrder` should contain the desired ordering of top-level categories; children keep their relative order.
    func reorderCategories(to newOrder: [Category]) async {
        guard let sid = spreadsheetId else { return }
        var updated = categories
        // Update order only for the provided top-level categories.
        for (index, cat) in newOrder.enumerated() {
            if let i = updated.firstIndex(where: { $0.id == cat.id }) {
                updated[i].order = index
            }
        }
        categories = updated
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Categories")
            let header = [Category.columnOrder]
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: header)
            let rows = updated.map { [$0.id, $0.name, "\($0.order)", $0.parentId ?? ""] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: rows)
            }
            if let data = try? JSONEncoder().encode(rows) {
                UserDefaults.standard.set(data, forKey: categoriesCacheKey)
            }
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    /// Reorders child categories within a single parent, preserving other categories.
    func reorderChildCategories(parentId: String, to newOrder: [Category]) async {
        guard let sid = spreadsheetId else { return }
        var updated = categories

        // Update order only for the provided children of this parent.
        for (index, cat) in newOrder.enumerated() {
            if let i = updated.firstIndex(where: { $0.id == cat.id }) {
                updated[i].order = index
            }
        }
        categories = updated

        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Categories")
            let header = [Category.columnOrder]
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: header)
            let rows = updated.map { [$0.id, $0.name, "\($0.order)", $0.parentId ?? ""] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: rows)
            }
            if let data = try? JSONEncoder().encode(rows) {
                UserDefaults.standard.set(data, forKey: categoriesCacheKey)
            }
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }
}
