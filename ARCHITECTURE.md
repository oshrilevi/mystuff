# MyStuff – Architecture

High-level structure for maintainers. See [docs/DATA_SCHEMA.md](docs/DATA_SCHEMA.md) for Sheets/Drive schema and [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for how to add features.

## Overview

- **Platform:** Native Swift/SwiftUI, single target for **macOS** and **iPhone** (conditional `#if os(iOS)` / `os(macOS)` where needed).
- **Data:** Google Sheets (12 sheets), Google Drive (photos + documents). One spreadsheet and one Drive folder per user; IDs stored in `UserDefaults` via `AppState`.
- **Auth:** Google Sign-In (OAuth 2.0, iOS client). `GoogleAuthService` is the single source of sign-in state and tokens.

## Entry & flow

1. **MyStuffApp** – `@main`, holds `GoogleAuthService` as `@StateObject`, passes it via `environmentObject` to `RootView`.
2. **RootView** – Decides what to show:
   - Not signed in → `SignInView`
   - Signed in, no `Session` → creates `Session(authService:)`, shows "Setting up…"
   - Bootstrap (spreadsheet/folder creation) running or failed → progress/error UI
   - Ready → `MainTabView` with `Session` in environment
3. **Session** – Created once per sign-in. Owns all services and ViewModels (see below). Runs `bootstrap()` to create/link spreadsheet and Drive folders, then loads all ViewModels.

## Folder layout

```
MyStuff/
├── MyStuffApp.swift
├── Models/
│   ├── Item.swift            # Item model, columnOrder, condition presets, price formatting
│   ├── Category.swift        # Category model, columnOrder, isWishlist helper
│   ├── Location.swift        # Storage location model
│   ├── UserStore.swift       # User-managed store (in-app browser)
│   ├── UserSource.swift      # User-managed source (in-app browser)
│   ├── ItemAttachment.swift  # Invoice/manual attachment model
│   ├── List.swift            # Packing list model
│   ├── ListItem.swift        # Item inside a packing list
│   ├── Combo.swift           # Item bundle (combo) model
│   ├── ComboItem.swift       # Item inside a combo
│   ├── Trip.swift            # Trip model (name, description, tags, lat/lon)
│   ├── TripLocation.swift    # Reusable named spot (nature reserve, trail, etc.)
│   └── TripVisit.swift       # Wildlife/nature sighting on a trip; sightings: [VisitSighting]
├── ViewModels/
│   ├── InventoryViewModel.swift    # Items CRUD, filter, search, photo cache
│   ├── CategoriesViewModel.swift   # Categories CRUD
│   ├── LocationsViewModel.swift    # Locations CRUD, default location in UserDefaults
│   ├── StoresViewModel.swift       # User-managed stores CRUD
│   ├── SourcesViewModel.swift      # User-managed sources CRUD
│   ├── AttachmentsViewModel.swift  # Item document attachments CRUD
│   ├── ListsViewModel.swift        # Packing lists + list items CRUD
│   ├── CombosViewModel.swift       # Combos + combo items CRUD
│   └── TripsViewModel.swift        # Trips + TripLocations + TripVisits CRUD
├── Views/
│   ├── RootView.swift, SignInView.swift, MainTabView.swift, UserAvatarMenuView.swift
│   ├── GalleryView.swift, ItemsListView.swift, ItemDetailView.swift, ItemFormView.swift, ItemSelectionView.swift
│   ├── CategoriesView.swift
│   ├── LocationsView.swift
│   ├── StoresView.swift, SourcesView.swift, AmazonBrowserView.swift, SourceBrowserView.swift, YouTubeSearchView.swift
│   ├── ListsView.swift, ListDetailView.swift
│   ├── CombosView.swift, ComboDetailView.swift
│   ├── TripsView.swift, TripDetailView.swift, TripMapView.swift  (+ trip-related sheets)
│   ├── DriveImageView.swift, CameraImagePicker.swift, MacCameraCaptureView.swift, PHAssetThumbnail.swift
│   ├── DocumentPreviewView.swift, PDFExportBuilder.swift, ExportMenuView.swift
│   └── TagChipsView.swift, NodeGraphView.swift, GraphLayoutEngine.swift
├── Services/
│   ├── GoogleAuthService.swift    # Sign-in, token, user profile
│   ├── Session.swift              # Session container, bootstrap, all ViewModels
│   ├── AppState.swift             # spreadsheetId, driveFolderId, bootstrap, UserDefaults
│   ├── SheetsService.swift        # Sheets API (create sheet, read/append/update rows)
│   ├── DriveService.swift         # Drive API (folder, upload, get image/doc)
│   ├── ExportService.swift        # CSV and PDF export generation
│   ├── PageMetadataService.swift  # Web page scraping (title, description, price)
│   ├── BrowserPriceService.swift  # JS-rendered price extraction (Amazon etc.)
│   ├── PhotoStorageService.swift
│   ├── WikipediaService.swift
│   ├── INaturalistService.swift
│   └── AmazonThumbnailService.swift
├── Info.plist
├── MyStuff.entitlements
└── Assets.xcassets
```

## Key components

| Component | Role |
|----------|------|
| **GoogleAuthService** | Sign-in state, `getAccessToken()`, `currentUser`. Used by Session and by Views for sign-out. |
| **AppState** | Holds `spreadsheetId` and `driveFolderId`; persists in UserDefaults; runs `bootstrapIfNeeded` (create spreadsheet + folders). |
| **SheetsService** | Token-based HTTP client for Sheets API. Create spreadsheet, get/append/update/batch-delete rows. No SwiftUI. |
| **DriveService** | Token-based HTTP client for Drive API. Create folder, upload image/doc, fetch file. No SwiftUI. |
| **Session** | Wires auth → sheets/drive tokenProvider, creates all ViewModels, runs bootstrap and initial load. |
| **InventoryViewModel** | Items list, filtered items, load/save/delete items, photo IDs; uses Sheets + Drive; optional offline cache. |
| **CategoriesViewModel** | Categories list, load/save/delete; uses Sheets only. |
| **LocationsViewModel** | Locations list, load/save/delete; stores default location ID in UserDefaults. |
| **StoresViewModel** | User-managed in-app browser stores; seeded with Amazon/AliExpress/B&H on new spreadsheets. |
| **SourcesViewModel** | User-managed in-app browser sources. |
| **AttachmentsViewModel** | Item document attachments (invoices, manuals); uses Sheets + Drive. |
| **ListsViewModel** | Packing lists + list items (two sheets: Lists + ListItems). |
| **CombosViewModel** | Item bundles + combo items (two sheets: Combos + ComboItems). |
| **TripsViewModel** | Trips + TripLocations + TripVisits (three sheets). Publishes `trips`, `tripLocations`, `tripVisits`. |

## Session ViewModels at a glance

```swift
session.inventory     // InventoryViewModel  — session.inventory.items
session.categories    // CategoriesViewModel — session.categories.categories
session.locations     // LocationsViewModel  — session.locations.locations
session.stores        // StoresViewModel     — session.stores.stores
session.sources       // SourcesViewModel    — session.sources.sources
session.attachments   // AttachmentsViewModel
session.lists         // ListsViewModel      — session.lists.lists, session.lists.listItems
session.combos        // CombosViewModel     — session.combos.combos, session.combos.comboItems
session.trips         // TripsViewModel      — session.trips.trips, .tripLocations, .tripVisits
session.drive         // DriveService        — used directly by views for image fetching
```

## Data flow (typical)

- **Load items:** View calls `session.inventory.refresh()`; ViewModel uses `SheetsService.getValues` for "Items" sheet, parses rows into `Item`, publishes `items`.
- **Add item:** View submits form; ViewModel uploads photos via `DriveService`, then appends row via `SheetsService`.
- **Categories, Locations, etc.:** Same pattern — ViewModel + `SheetsService` for the relevant sheet.
- **Bootstrap:** On first run, `AppState.bootstrapIfNeeded` creates spreadsheet (with all header rows) and "MyStuff Photos" / "MyStuff Documents" Drive folders, saves IDs to UserDefaults. Subsequent sheets (Locations, Stores, etc.) are added lazily by each ViewModel on first load.

## Conventions

- ViewModels are `@MainActor` and `ObservableObject`; they hold `@Published` state and call services (which are not actors).
- Services are plain classes; they take a `tokenProvider: () async throws -> String` and do not hold UI state.
- Models define `columnOrder` and use it for row serialization; parsing is in the ViewModel that owns the sheet.
- New columns are always **appended** to `columnOrder`; parsing must default missing columns for backward compatibility.

## Dependencies

- **Google Sign-In:** [GoogleSignIn-iOS](https://github.com/google/GoogleSignIn-iOS) (GoogleSignIn + GoogleSignInSwift). Bundle ID must match OAuth client: `com.mystuff.inventory`.
