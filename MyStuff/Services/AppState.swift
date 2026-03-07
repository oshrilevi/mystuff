import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var spreadsheetId: String?
    @Published var driveFolderId: String?
    @Published var bootstrapError: String?
    @Published var isBootstrapping = false
    @Published var bootstrapStep: String = ""

    private let defaults = UserDefaults.standard
    private let spreadsheetKey = "mystuff_spreadsheet_id"
    private let folderKey = "mystuff_drive_folder_id"

    init() {
        spreadsheetId = defaults.string(forKey: spreadsheetKey)
        driveFolderId = defaults.string(forKey: folderKey)
    }

    func bootstrapIfNeeded(sheets: SheetsService, drive: DriveService, userEmail: String) async {
        if spreadsheetId != nil, driveFolderId != nil { return }
        isBootstrapping = true
        bootstrapError = nil
        defer { isBootstrapping = false; bootstrapStep = "" }
        do {
            if spreadsheetId == nil {
                bootstrapStep = "Creating spreadsheet…"
                let title = "MyStuff – \(userEmail)"
                let (id, _) = try await sheets.createSpreadsheet(title: title)
                spreadsheetId = id
                defaults.set(id, forKey: spreadsheetKey)
            }
            if driveFolderId == nil {
                bootstrapStep = "Creating photo folder…"
                let folderId = try await drive.createFolder(name: "MyStuff Photos")
                driveFolderId = folderId
                defaults.set(folderId, forKey: folderKey)
            }
        } catch {
            bootstrapError = error.localizedDescription
        }
    }

    func clearStoredIds() {
        spreadsheetId = nil
        driveFolderId = nil
        defaults.removeObject(forKey: spreadsheetKey)
        defaults.removeObject(forKey: folderKey)
    }
}
