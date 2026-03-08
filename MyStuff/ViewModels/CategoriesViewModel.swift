import Foundation
import SwiftUI

@MainActor
final class CategoriesViewModel: ObservableObject {
    @Published var categories: [Category] = []
    @Published var pinnedCategoryIds: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?

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
                return Category(id: row[0], name: row[1], order: order)
            }
            categories = loaded
            if let data = try? JSONEncoder().encode(loaded.map { [$0.id, $0.name, "\($0.order)"] }) {
                UserDefaults.standard.set(data, forKey: categoriesCacheKey)
            }
        } catch {
            errorMessage = error.localizedDescription
            if let data = UserDefaults.standard.data(forKey: categoriesCacheKey),
               let rows = try? JSONDecoder().decode([[String]].self, from: data) {
                let cached: [Category] = rows.enumerated().compactMap { index, row in
                    guard row.count >= 2 else { return nil }
                    return Category(id: row[0], name: row[1], order: index + 2)
                }
                categories = cached
            }
        }
    }

    func addCategory(name: String) async {
        guard let sid = spreadsheetId else { return }
        let category = Category(name: name, order: categories.count)
        let values = [[category.id, category.name, "\(category.order)"]]
        do {
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: values)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateCategory(id: String, name: String) async {
        guard let sid = spreadsheetId else { return }
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        var updated = categories
        updated[index].name = name
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Categories")
            let header = [["id", "name", "order"]]
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: header)
            let rows = updated.map { [$0.id, $0.name, "\($0.order)"] }
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
            let header = [["id", "name", "order"]]
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: header)
            let rows = updated.map { [$0.id, $0.name, "\($0.order)"] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Categories", values: rows)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
