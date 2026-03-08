# MyStuff – Development Guide

For maintainers and contributors. See [ARCHITECTURE.md](../ARCHITECTURE.md) for structure and [DATA_SCHEMA.md](DATA_SCHEMA.md) for Sheets/Drive schema.

## Prerequisites

- Xcode (current stable)
- Apple Developer account (for signing; Simulator can work without)
- Google Cloud project with Sheets + Drive APIs and iOS OAuth client (see [README](../README.md))

## Opening the project

- Open **MyStuff.xcodeproj** in Xcode.
- Select scheme **MyStuff** and destination **My Mac** or an iPhone simulator.
- Build: ⌘B, Run: ⌘R.

## Codebase conventions

- **SwiftUI** for all UI. Use `#if os(iOS)` / `#elseif os(macOS)` only when the API differs (e.g. `UIImage` vs `NSImage`, camera APIs).
- **ViewModels:** `@MainActor`, `ObservableObject`, `@Published` for state. They call `SheetsService` / `DriveService`; they do not import SwiftUI beyond what’s needed for types.
- **Services:** Plain classes, no `@MainActor`. They take a `tokenProvider` (or similar) and perform async API calls. Keep them free of UI and ViewModels.
- **Models:** Structs in `Models/`. Define `columnOrder` and keep parsing logic in the ViewModel that owns the sheet (e.g. `InventoryViewModel` for Items).

## Where to add things

| Goal | Where to change |
|------|------------------|
| New **item field** (e.g. “location”) | 1) `Item` in `Models/Item.swift` (property + `columnOrder`). 2) `InventoryViewModel`: `itemToRow`, `parseItemRow`, and any create/update that writes rows. 3) `ItemFormView` (and detail/list if you show it). 4) If you add a column, consider [DATA_SCHEMA.md](DATA_SCHEMA.md) and migration for existing spreadsheets. |
| New **category field** | 1) `Category` in `Models/Category.swift` (property + `columnOrder`). 2) `CategoriesViewModel`: row encoding/parsing, add/update. 3) `CategoriesView` (and any pickers). |
| New **location field** / **Locations** management | 1) `Location` in `Models/Location.swift` and `Item.locationId`; 2) `LocationsViewModel` (load/add/update/delete, default location in UserDefaults); 3) `LocationsView`; 4) `ItemFormView`, `ItemDetailView`, list row, popover for display. See [DATA_SCHEMA.md](DATA_SCHEMA.md) for Locations sheet and `mystuff_default_location_id`. |
| New **tab or main screen** | `MainTabView` + new View + optional ViewModel. Pass `Session` (or specific ViewModels) via `environmentObject`. For **stores** (in-app browser): add a case to the `Store` enum in `AmazonBrowserView.swift`, then add a tab or sidebar link to `StoreBrowserView(store: .yourStore)`. Example stores: Amazon, AliExpress, B&H Photo. |
| New **API call** (Sheets/Drive) | Implement in `SheetsService` or `DriveService`; call from the appropriate ViewModel. |
| Change **bootstrap** (e.g. new sheet) | `AppState.bootstrapIfNeeded` and `SheetsService.createSpreadsheet` (and any code that expects sheet names). |
| Auth / sign-out behavior | `GoogleAuthService` and views that use it (`RootView`, `SignInView`, `UserAvatarMenuView`). |

## Testing

- Run on **My Mac** and **iPhone Simulator** after changes that touch UI or platform-specific code (camera, etc.).
- After changing **Item** or **Category** schema, test with a **new** spreadsheet (new user or cleared `spreadsheetId`/`driveFolderId`) and with an **existing** one if you kept backward compatibility in parsing.

## Releasing / version bumps

- Update **version and build** in Xcode (target → General → Version / Build).
- Note changes in [CHANGELOG.md](../CHANGELOG.md).
- If you changed **Item** or **Category** columns, document it in [DATA_SCHEMA.md](DATA_SCHEMA.md) and any migration steps.

## Common issues

- **“No such module 'GoogleSignIn'”** – Add package dependency and add GoogleSignIn + GoogleSignInSwift to the MyStuff target (see README).
- **400 / malformed on sign-in** – Wrong or placeholder Client ID / URL scheme in `Info.plist` (see README).
- **Build fails on signing** – Set Team under Signing & Capabilities; clean build folder (⇧⌘K) and try again.
- **Sheets or Drive errors** – Ensure APIs are enabled and OAuth scopes include `spreadsheets` and `drive.file`; token is refreshed via `GoogleAuthService`.
