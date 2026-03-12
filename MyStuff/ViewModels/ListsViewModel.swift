import Foundation
import SwiftUI

@MainActor
final class ListsViewModel: ObservableObject {
    @Published var lists: [UserList] = []
    @Published var listItems: [ListItem] = []
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

    var filteredLists: [UserList] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return lists.sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
        }
        let q = searchText.lowercased()
        return lists
            .filter { list in
                list.name.lowercased().contains(q) ||
                list.notes.lowercased().contains(q)
            }
            .sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    func items(for list: UserList, from items: [Item]) -> [Item] {
        let entries = listItems.filter { $0.listId == list.id }
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
            let listRows = try await sheets.getValues(spreadsheetId: sid, range: "Lists!A2:Z1000")
            let itemRows = try await sheets.getValues(spreadsheetId: sid, range: "ListItems!A2:Z5000")
            lists = parseLists(from: listRows)
            listItems = parseListItems(from: itemRows)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addList(name: String, notes: String = "") async {
        guard let sid = spreadsheetId else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (lists.map { $0.order }.max() ?? 0) + 1
        let list = UserList(name: trimmed, notes: notes, order: nextOrder)
        let values = [[
            list.id,
            list.name,
            list.notes,
            "\(list.order)",
            list.createdAt,
            list.updatedAt
        ]]
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Lists", values: values)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateList(_ list: UserList) async {
        guard let sid = spreadsheetId else { return }
        guard let index = lists.firstIndex(where: { $0.id == list.id }) else { return }
        var updatedLists = lists
        var updated = list
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        updatedLists[index] = updated
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Lists")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Lists", values: [UserList.columnOrder])
            if !updatedLists.isEmpty {
                let rows = updatedLists.map { list in
                    [
                        list.id,
                        list.name,
                        list.notes,
                        "\(list.order)",
                        list.createdAt,
                        list.updatedAt
                    ]
                }
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Lists", values: rows)
            }
            lists = updatedLists
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteLists(_ listsToDelete: [UserList]) async {
        guard let sid = spreadsheetId else { return }
        let idsToDelete = Set(listsToDelete.map { $0.id })
        let remainingLists = lists.filter { !idsToDelete.contains($0.id) }
        let remainingListItems = listItems.filter { !idsToDelete.contains($0.listId) }
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Lists")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Lists", values: [UserList.columnOrder])
            if !remainingLists.isEmpty {
                let rows = remainingLists.map { list in
                    [
                        list.id,
                        list.name,
                        list.notes,
                        "\(list.order)",
                        list.createdAt,
                        list.updatedAt
                    ]
                }
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Lists", values: rows)
            }

            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "ListItems")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "ListItems", values: [ListItem.columnOrder])
            if !remainingListItems.isEmpty {
                let rows = remainingListItems.map { entry in
                    [
                        entry.id,
                        entry.listId,
                        entry.itemId,
                        "\(entry.order)",
                        entry.note
                    ]
                }
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "ListItems", values: rows)
            }

            lists = remainingLists
            listItems = remainingListItems
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addItems(_ items: [Item], to list: UserList) async {
        guard let sid = spreadsheetId else { return }
        guard !items.isEmpty else { return }
        let existingForList = listItems.filter { $0.listId == list.id }
        let existingIds = Set(existingForList.map { $0.itemId })
        let newItems = items.filter { !existingIds.contains($0.id) }
        guard !newItems.isEmpty else { return }
        let startOrder = (existingForList.map { $0.order }.max() ?? 0) + 1
        var nextOrder = startOrder
        var newEntries: [ListItem] = []
        for item in newItems {
            newEntries.append(ListItem(listId: list.id, itemId: item.id, order: nextOrder, note: ""))
            nextOrder += 1
        }
        let rows = newEntries.map { entry in
            [
                entry.id,
                entry.listId,
                entry.itemId,
                "\(entry.order)",
                entry.note
            ]
        }
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "ListItems", values: rows)
            listItems.append(contentsOf: newEntries)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeItems(_ items: [Item], from list: UserList) async {
        guard let sid = spreadsheetId else { return }
        guard !items.isEmpty else { return }
        let idsToRemove = Set(items.map { $0.id })
        let remaining = listItems.filter { !($0.listId == list.id && idsToRemove.contains($0.itemId)) }
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "ListItems")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "ListItems", values: [ListItem.columnOrder])
            if !remaining.isEmpty {
                let rows = remaining.map { entry in
                    [
                        entry.id,
                        entry.listId,
                        entry.itemId,
                        "\(entry.order)",
                        entry.note
                    ]
                }
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "ListItems", values: rows)
            }
            listItems = remaining
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureSheetsExist(spreadsheetId sid: String) async throws {
        let titles = try await sheets.getSheetTitles(spreadsheetId: sid)
        if !titles.contains("Lists") {
            try await sheets.addSheet(spreadsheetId: sid, title: "Lists")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Lists", values: [UserList.columnOrder])
        }
        if !titles.contains("ListItems") {
            try await sheets.addSheet(spreadsheetId: sid, title: "ListItems")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "ListItems", values: [ListItem.columnOrder])
        }
    }

    private func parseLists(from rows: [[String]]) -> [UserList] {
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
            return UserList(
                id: row[0],
                name: name,
                notes: notes,
                order: order,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private func parseListItems(from rows: [[String]]) -> [ListItem] {
        rows.enumerated().compactMap { index, row in
            guard row.count >= 3 else { return nil }
            let order: Int
            if row.count > 3 {
                order = Int(row[3].trimmingCharacters(in: .whitespaces)) ?? index
            } else {
                order = index
            }
            let note = row.count > 4 ? row[4] : ""
            return ListItem(
                id: row[0],
                listId: row[1],
                itemId: row[2],
                order: order,
                note: note
            )
        }
    }
}

