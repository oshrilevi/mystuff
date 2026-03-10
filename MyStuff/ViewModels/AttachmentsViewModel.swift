import Foundation
import SwiftUI

@MainActor
final class AttachmentsViewModel: ObservableObject {
    @Published var attachments: [ItemAttachment] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sheets: SheetsService
    private let drive: DriveService
    private var spreadsheetId: String? { appState.spreadsheetId }
    private var documentsFolderId: String? { appState.driveDocumentsFolderId }
    private let appState: AppState

    init(sheets: SheetsService, drive: DriveService, appState: AppState) {
        self.sheets = sheets
        self.drive = drive
        self.appState = appState
    }

    func attachments(for itemId: String) -> [ItemAttachment] {
        attachments.filter { $0.itemId == itemId }
    }

    func load() async {
        guard let sid = spreadsheetId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let titles = try await sheets.getSheetTitles(spreadsheetId: sid)
            if !titles.contains("Attachments") {
                try await sheets.addSheet(spreadsheetId: sid, title: "Attachments")
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Attachments", values: [ItemAttachment.columnOrder])
            }
            let rows: [[String]] = try await sheets.getValues(spreadsheetId: sid, range: "Attachments!A2:Z1000")
            attachments = rows.compactMap { parseRow($0) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addAttachment(itemId: String, fileData: Data, mimeType: String, filename: String, kind: ItemAttachment.Kind, displayName: String) async {
        errorMessage = nil
        guard let sid = spreadsheetId, let fid = documentsFolderId else {
            errorMessage = "Documents folder not ready. Please quit and reopen the app, then try again."
            return
        }
        do {
            let driveFileId = try await drive.uploadFile(data: fileData, mimeType: mimeType, filename: filename, parentFolderId: fid)
            let attachment = ItemAttachment(itemId: itemId, driveFileId: driveFileId, kind: kind, displayName: displayName.isEmpty ? filename : displayName)
            let row = attachmentToRow(attachment)
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Attachments", values: [row])
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAttachment(id: String) async {
        guard let sid = spreadsheetId else { return }
        let updated = attachments.filter { $0.id != id }
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Attachments")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Attachments", values: [ItemAttachment.columnOrder])
            if !updated.isEmpty {
                let rows = updated.map { attachmentToRow($0) }
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Attachments", values: rows)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Removes all attachments for the given item IDs (e.g. when items are deleted).
    func removeAttachments(forItemIds itemIds: Set<String>) async {
        guard let sid = spreadsheetId else { return }
        let updated = attachments.filter { !itemIds.contains($0.itemId) }
        do {
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Attachments")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Attachments", values: [ItemAttachment.columnOrder])
            if !updated.isEmpty {
                let rows = updated.map { attachmentToRow($0) }
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Attachments", values: rows)
            }
            attachments = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attachmentToRow(_ a: ItemAttachment) -> [String] {
        [a.id, a.itemId, a.driveFileId, a.kind.rawValue, a.displayName, a.createdAt]
    }

    private func parseRow(_ row: [String]) -> ItemAttachment? {
        guard row.count >= 3 else { return nil }
        let kind: ItemAttachment.Kind
        if row.count > 3, let k = ItemAttachment.Kind(rawValue: row[3]) {
            kind = k
        } else {
            kind = .other
        }
        let displayName = row.count > 4 ? row[4] : ""
        let createdAt = row.count > 5 ? row[5] : ""
        return ItemAttachment(
            id: row[0],
            itemId: row[1],
            driveFileId: row[2],
            kind: kind,
            displayName: displayName,
            createdAt: createdAt
        )
    }
}
