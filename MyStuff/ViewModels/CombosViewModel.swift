import Foundation
import SwiftUI

@MainActor
final class CombosViewModel: ObservableObject {
    @Published var combos: [Combo] = []
    @Published var comboItems: [ComboItem] = []
    @Published var searchText: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sheets: SheetsService
    private var spreadsheetId: String? { appState.spreadsheetId }
    private let appState: AppState

    init(sheets: SheetsService, appState: AppState) {
        self.sheets = sheets
        self.appState = appState
    }

    var filteredCombos: [Combo] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return combos.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        let q = searchText.lowercased()
        return combos
            .filter { combo in
                combo.name.lowercased().contains(q) ||
                combo.notes.lowercased().contains(q)
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func items(for combo: Combo, from items: [Item]) -> [Item] {
        let entries = comboItems.filter { $0.comboId == combo.id }
        if entries.isEmpty { return [] }
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let sortedEntries = entries.sorted { ($0.order, $0.itemId) < ($1.order, $1.itemId) }
        return sortedEntries.compactMap { byId[$0.itemId] }
    }

    func load() async {
        guard let sid = spreadsheetId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            let comboRows = try await sheets.getValues(spreadsheetId: sid, range: "Combos!A2:Z1000")
            let itemRows = try await sheets.getValues(spreadsheetId: sid, range: "ComboItems!A2:Z5000")
            combos = parseCombos(from: comboRows)
            comboItems = parseComboItems(from: itemRows)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addCombo(name: String, notes: String = "") async {
        guard let sid = spreadsheetId else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (combos.map { $0.order }.max() ?? 0) + 1
        let combo = Combo(name: trimmed, notes: notes, order: nextOrder)
        let values = [[
            combo.id,
            combo.name,
            combo.notes,
            "\(combo.order)",
            combo.createdAt,
            combo.updatedAt
        ]]
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Combos", values: values)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateCombo(_ combo: Combo) async {
        guard let sid = spreadsheetId else { return }
        guard let index = combos.firstIndex(where: { $0.id == combo.id }) else { return }
        var updatedCombos = combos
        var updated = combo
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        updatedCombos[index] = updated
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Combos")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Combos", values: [Combo.columnOrder])
            if !updatedCombos.isEmpty {
                let rows = updatedCombos.map { combo in
                    [
                        combo.id,
                        combo.name,
                        combo.notes,
                        "\(combo.order)",
                        combo.createdAt,
                        combo.updatedAt
                    ]
                }
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Combos", values: rows)
            }
            combos = updatedCombos
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCombos(_ combosToDelete: [Combo]) async {
        guard let sid = spreadsheetId else { return }
        let idsToDelete = Set(combosToDelete.map { $0.id })
        let remainingCombos = combos.filter { !idsToDelete.contains($0.id) }
        let remainingComboItems = comboItems.filter { !idsToDelete.contains($0.comboId) }
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Combos")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Combos", values: [Combo.columnOrder])
            if !remainingCombos.isEmpty {
                let rows = remainingCombos.map { combo in
                    [
                        combo.id,
                        combo.name,
                        combo.notes,
                        "\(combo.order)",
                        combo.createdAt,
                        combo.updatedAt
                    ]
                }
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Combos", values: rows)
            }

            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "ComboItems")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "ComboItems", values: [ComboItem.columnOrder])
            if !remainingComboItems.isEmpty {
                let rows = remainingComboItems.map { entry in
                    [
                        entry.id,
                        entry.comboId,
                        entry.itemId,
                        "\(entry.order)"
                    ]
                }
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "ComboItems", values: rows)
            }

            combos = remainingCombos
            comboItems = remainingComboItems
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addItems(_ items: [Item], to combo: Combo) async {
        guard let sid = spreadsheetId else { return }
        guard !items.isEmpty else { return }
        let existingForCombo = comboItems.filter { $0.comboId == combo.id }
        let existingIds = Set(existingForCombo.map { $0.itemId })
        let newItems = items.filter { !existingIds.contains($0.id) }
        guard !newItems.isEmpty else { return }
        let startOrder = (existingForCombo.map { $0.order }.max() ?? 0) + 1
        var nextOrder = startOrder
        var newEntries: [ComboItem] = []
        for item in newItems {
            newEntries.append(ComboItem(comboId: combo.id, itemId: item.id, order: nextOrder))
            nextOrder += 1
        }
        let rows = newEntries.map { entry in
            [
                entry.id,
                entry.comboId,
                entry.itemId,
                "\(entry.order)"
            ]
        }
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "ComboItems", values: rows)
            comboItems.append(contentsOf: newEntries)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeItems(_ items: [Item], from combo: Combo) async {
        guard let sid = spreadsheetId else { return }
        guard !items.isEmpty else { return }
        let idsToRemove = Set(items.map { $0.id })
        let remaining = comboItems.filter { !($0.comboId == combo.id && idsToRemove.contains($0.itemId)) }
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "ComboItems")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "ComboItems", values: [ComboItem.columnOrder])
            if !remaining.isEmpty {
                let rows = remaining.map { entry in
                    [
                        entry.id,
                        entry.comboId,
                        entry.itemId,
                        "\(entry.order)"
                    ]
                }
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "ComboItems", values: rows)
            }
            comboItems = remaining
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureSheetsExist(spreadsheetId sid: String) async throws {
        let titles = try await sheets.getSheetTitles(spreadsheetId: sid)
        if !titles.contains("Combos") {
            try await sheets.addSheet(spreadsheetId: sid, title: "Combos")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Combos", values: [Combo.columnOrder])
        }
        if !titles.contains("ComboItems") {
            try await sheets.addSheet(spreadsheetId: sid, title: "ComboItems")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "ComboItems", values: [ComboItem.columnOrder])
        }
    }

    private func parseCombos(from rows: [[String]]) -> [Combo] {
        rows.enumerated().compactMap { index, row in
            guard row.count >= 2 else { return nil }
            let order: Int
            if row.count > 3 {
                order = Int(row[3].trimmingCharacters(in: .whitespaces)) ?? index + 2
            } else {
                order = index + 2
            }
            let name = row[1]
            let notes = row.count > 2 ? row[2] : ""
            let createdAt = row.count > 4 ? row[4] : ""
            let updatedAt = row.count > 5 ? row[5] : ""
            return Combo(
                id: row[0],
                name: name,
                notes: notes,
                order: order,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private func parseComboItems(from rows: [[String]]) -> [ComboItem] {
        rows.enumerated().compactMap { index, row in
            guard row.count >= 3 else { return nil }
            let order: Int
            if row.count > 3 {
                order = Int(row[3].trimmingCharacters(in: .whitespaces)) ?? index
            } else {
                order = index
            }
            return ComboItem(
                id: row[0],
                comboId: row[1],
                itemId: row[2],
                order: order
            )
        }
    }
}

