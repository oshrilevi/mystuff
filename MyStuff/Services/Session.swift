import Foundation
import SwiftUI
import GoogleSignIn
import Combine

@MainActor
final class Session: ObservableObject {
    let appState: AppState
    let sheets: SheetsService
    let drive: DriveService
    let pageMetadata: PageMetadataService
    let inventory: InventoryViewModel
    let categories: CategoriesViewModel
    let wishlist: WishlistViewModel

    private let authService: GoogleAuthService
    private var cancellables = Set<AnyCancellable>()

    init(authService: GoogleAuthService) {
        self.authService = authService
        self.appState = AppState()
        self.sheets = SheetsService(tokenProvider: { [weak authService] in
            try await authService?.getAccessToken() ?? ""
        })
        self.drive = DriveService(tokenProvider: { [weak authService] in
            try await authService?.getAccessToken() ?? ""
        })
        self.pageMetadata = PageMetadataService()
        self.inventory = InventoryViewModel(sheets: self.sheets, drive: self.drive, appState: self.appState)
        self.categories = CategoriesViewModel(sheets: self.sheets, appState: self.appState)
        self.wishlist = WishlistViewModel(sheets: self.sheets, drive: self.drive, appState: self.appState)

        // Forward child view model updates so views observing Session re-render when items/categories load
        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        inventory.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        categories.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        wishlist.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func bootstrap() async {
        appState.bootstrapStep = "Getting token…"
        // Fail fast if getting the token hangs (common on Mac)
        let gotToken = await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                _ = try? await self.authService.getAccessToken()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        guard gotToken else {
            appState.bootstrapStep = ""
            appState.bootstrapError = "Getting access token timed out. Sign out and try again."
            return
        }

        let email = authService.currentUser?.profile?.email ?? "user"
        let timeout: UInt64 = 60_000_000_000 // 60 seconds
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                await self.appState.bootstrapIfNeeded(sheets: self.sheets, drive: self.drive, userEmail: email)
                if self.appState.bootstrapError == nil, let sid = self.appState.spreadsheetId {
                    try? await self.sheets.ensureWishlistSheetExists(spreadsheetId: sid)
                    await self.inventory.refresh()
                    await self.categories.load()
                    await self.wishlist.load()
                }
                return true
            }
            group.addTask { @MainActor in
                try? await Task.sleep(nanoseconds: timeout)
                if self.appState.spreadsheetId == nil, self.appState.bootstrapError == nil {
                    self.appState.bootstrapError = "Setup timed out. Check your internet connection and try again."
                }
                return false
            }
            _ = await group.next()
            group.cancelAll()
        }
    }
}
