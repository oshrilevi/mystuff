# MyStuff – Claude Code Instructions

## Project overview

Native **macOS + iOS** inventory management app built with **Swift/SwiftUI**. Data is stored in a **Google Spreadsheet** (12 sheets) and photos/documents in **Google Drive**. Single Xcode target, conditional `#if os(iOS)` / `#if os(macOS)` where APIs differ.

## Tech stack

- **Language:** Swift 5+, **UI:** SwiftUI, **Architecture:** MVVM
- **Auth:** Google Sign-In (GoogleSignIn-iOS, OAuth 2.0)
- **Backend:** Google Sheets API + Google Drive API (no server; plain HTTP in `SheetsService`/`DriveService`)
- **Platforms:** macOS 12+, iOS 14+, bundle ID `com.mystuff.inventory`

## Architecture

```
MyStuffApp → GoogleAuthService (StateObject)
           → RootView (auth routing)
               → Session (created once per sign-in)
                   ├── AppState           (spreadsheetId, driveFolderId, bootstrap, UserDefaults)
                   ├── SheetsService      (Google Sheets HTTP client; tokenProvider)
                   ├── DriveService       (Google Drive HTTP client; tokenProvider)
                   ├── PageMetadataService / BrowserPriceService
                   ├── InventoryViewModel (items, photos)
                   ├── CategoriesViewModel
                   ├── LocationsViewModel
                   ├── StoresViewModel
                   ├── SourcesViewModel
                   ├── AttachmentsViewModel
                   ├── ListsViewModel
                   ├── CombosViewModel
                   └── TripsViewModel     (trips, tripLocations, tripVisits)
               → MainTabView
```

## Key conventions

- **ViewModels:** `@MainActor`, `ObservableObject`, `@Published` state. Call `SheetsService` / `DriveService`. Never import UIKit/AppKit directly.
- **Services:** Plain classes, no `@MainActor`. Accept `tokenProvider: () async throws -> String`. No UI, no ViewModels.
- **Models:** Structs in `Models/`. Define `static let columnOrder` — array of column names matching Google Sheets column order. Row parsing lives in the ViewModel that owns the sheet (e.g. `InventoryViewModel.parseItemRow`).
- **New columns always appended** to `columnOrder` for backward compatibility; parsing must provide defaults for missing indices.
- **Platform branching:** `#if os(iOS)` / `#if os(macOS)` only where APIs differ (camera, image types, etc.).

## Sheets (12 total)

Categories, Items, Locations, Stores, Sources, Attachments, Lists, ListItems, Combos, ComboItems, Trips, TripLocations, TripVisits.

For full column-by-column schema see **[docs/DATA_SCHEMA.md](docs/DATA_SCHEMA.md)**.

## Where to add things

See **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** for the full "Where to add things" table. Quick reference:

| Task | Files to touch |
|------|----------------|
| New item field | `Models/Item.swift` → `InventoryViewModel` (parse/write) → `ItemFormView`/`ItemDetailView` → `DATA_SCHEMA.md` |
| New sheet / feature | New Model + ViewModel → Session init → `bootstrap` → View + `MainTabView` → `DATA_SCHEMA.md` + `DEVELOPMENT.md` |
| New API call | `SheetsService` or `DriveService` → call from ViewModel |
| Export change | `ExportService` → `ExportMenuView` |

## Schema change rule

When adding or changing a column: **Model → ViewModel (parse + write) → View → DATA_SCHEMA.md → bootstrap headers → CHANGELOG.md**. Always preserve backward-compatible parsing for existing spreadsheets.

## Domain notes

- **Wishlist items** use **USD** as the price currency (`priceCurrency` column). Standard items store prices in NIS (or leave `priceCurrency` empty = NIS).
- **TripVisits** represent wildlife/nature sightings on trips; `sightings` column is JSON-encoded `[VisitSighting]`.
- **TripLocations** are reusable named spots (nature reserves, trails, etc.) referenced by trips via `locationIds`.
- **Bootstrap** (`AppState.bootstrapIfNeeded`) creates the spreadsheet + Drive folders on first run. New sheets are created lazily by each ViewModel on first load (migration pattern).

## Git / commits

**Never commit changes unless explicitly asked.** Always check with the user before running `git commit`, `git push`, or any destructive git operation.

## Detailed docs

- **[ARCHITECTURE.md](ARCHITECTURE.md)** — Component roles, data flow, dependency graph
- **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** — Conventions, where to add things, testing, releases
- **[docs/DATA_SCHEMA.md](docs/DATA_SCHEMA.md)** — Full Sheets/Drive schema, UserDefaults keys, cache locations
