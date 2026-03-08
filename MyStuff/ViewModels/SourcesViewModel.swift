import Foundation
import SwiftUI

@MainActor
final class SourcesViewModel: ObservableObject {
    @Published var sources: [UserSource] = []
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
            if !titles.contains("Sources") {
                try await sheets.addSheet(spreadsheetId: sid, title: "Sources")
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Sources", values: [UserSource.columnOrder])
            }
            let rows: [[String]] = try await sheets.getValues(spreadsheetId: sid, range: "Sources!A2:Z500")
            let loaded: [UserSource] = rows.enumerated().compactMap { index, row in
                guard row.count >= 2 else { return nil }
                let order = row.count > 3 ? (Int(row[3]) ?? index) : index
                let urlString = row.count > 2 ? row[2] : "https://"
                return UserSource(id: row[0], name: row[1], url: urlString, order: order)
            }
            sources = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addSource(name: String, url: String) async {
        guard let sid = spreadsheetId else { return }
        let source = UserSource(name: name, url: url, order: sources.count)
        let values = [[source.id, source.name, source.url, "\(source.order)"]]
        do {
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Sources", values: values)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSource(id: String, name: String, url: String) async {
        guard let sid = spreadsheetId else { return }
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        var updated = sources
        updated[index].name = name
        updated[index].url = url
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Sources")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Sources", values: [UserSource.columnOrder])
            let rows = updated.map { [$0.id, $0.name, $0.url, "\($0.order)"] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Sources", values: rows)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSources(ids: [String]) async {
        guard let sid = spreadsheetId else { return }
        let idSet = Set(ids)
        let updated = sources.filter { !idSet.contains($0.id) }
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Sources")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Sources", values: [UserSource.columnOrder])
            let rows = updated.map { [$0.id, $0.name, $0.url, "\($0.order)"] }
            if !rows.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Sources", values: rows)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
