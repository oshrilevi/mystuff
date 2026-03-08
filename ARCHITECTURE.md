# MyStuff – Architecture

High-level structure for maintainers. See [docs/DATA_SCHEMA.md](docs/DATA_SCHEMA.md) for Sheets/Drive schema and [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for how to add features.

## Overview

- **Platform:** Native Swift/SwiftUI, single target for **macOS** and **iPhone** (conditional `#if os(iOS)` / `os(macOS)` where needed).
- **Data:** Google Sheets (items + categories), Google Drive (photos). One spreadsheet and one Drive folder per user; IDs stored in `UserDefaults` via `AppState`.
- **Auth:** Google Sign-In (OAuth 2.0, iOS client). `GoogleAuthService` is the single source of sign-in state and tokens.

## Entry & flow

1. **MyStuffApp** – `@main`, holds `GoogleAuthService` as `@StateObject`, passes it via `environmentObject` to `RootView`.
2. **RootView** – Decides what to show:
   - Not signed in → `SignInView`
   - Signed in, no `Session` → creates `Session(authService:)`, shows “Setting up…”
   - Bootstrap (spreadsheet/folder creation) running or failed → progress/error UI
   - Ready → `MainTabView` with `Session` in environment
3. **Session** – Created once per sign-in. Owns:
   - `AppState` (spreadsheetId, driveFolderId, bootstrap state)
   - `SheetsService`, `DriveService` (token from `GoogleAuthService`)
   - `PageMetadataService`
   - `InventoryViewModel`, `CategoriesViewModel`
   Session runs `bootstrap()` to create/link spreadsheet and Drive folder, then loads categories (and inventory refresh).

## Folder layout

```
MyStuff/
├── MyStuffApp.swift          # App entry, auth env
├── Models/
│   ├── Item.swift            # Item model + column order, condition presets, price formatting
│   └── Category.swift        # Category model + column order, isWishlist
├── ViewModels/
│   ├── InventoryViewModel.swift   # Items CRUD, filter, search, cache
│   └── CategoriesViewModel.swift  # Categories CRUD
├── Views/
│   ├── RootView.swift        # Auth + bootstrap routing
│   ├── MainTabView.swift     # Tab bar (Gallery, List, Categories, etc.)
│   ├── SignInView.swift
│   ├── GalleryView.swift, ItemsListView.swift, ItemDetailView.swift, ItemFormView.swift
│   ├── CategoriesView.swift
│   ├── UserAvatarMenuView.swift
│   ├── DriveImageView.swift, CameraImagePicker.swift, MacCameraCaptureView.swift
│   └── ...
├── Services/
│   ├── GoogleAuthService.swift   # Sign-in, token, user profile
│   ├── Session.swift            # Session container, bootstrap
│   ├── AppState.swift           # spreadsheetId, driveFolderId, bootstrap, UserDefaults
│   ├── SheetsService.swift      # Sheets API (create sheet, read/append/update rows)
│   ├── DriveService.swift       # Drive API (folder, upload, get image)
│   └── PageMetadataService.swift
├── Info.plist
├── MyStuff.entitlements
└── Assets.xcassets
```

## Key components

| Component | Role |
|----------|------|
| **GoogleAuthService** | Sign-in state, `getAccessToken()`, `currentUser`. Used by Session and by Views for sign-out. |
| **AppState** | Holds `spreadsheetId` and `driveFolderId`; persists in UserDefaults; runs `bootstrapIfNeeded` (create spreadsheet + folder). |
| **SheetsService** | Token-based HTTP client for Sheets API. Create spreadsheet, get/append/update rows. No SwiftUI. |
| **DriveService** | Token-based HTTP client for Drive API. Create folder, upload image, fetch file. No SwiftUI. |
| **Session** | Wires auth → sheets/drive tokenProvider, creates ViewModels, runs bootstrap and initial load. |
| **InventoryViewModel** | Items list, filtered items, load/save/delete items, photo IDs; uses Sheets + Drive; optional offline cache. |
| **CategoriesViewModel** | Categories list, load/save/delete; uses Sheets only. |

## Data flow (typical)

- **Load items:** View calls `inventory.loadItems()` (or `refresh()`); ViewModel uses `SheetsService.getValues` for "Items" sheet, parses rows into `Item`, publishes `items`.
- **Add item:** View submits form; ViewModel uploads photos via `DriveService`, then appends/updates row via `SheetsService`.
- **Categories:** Same idea: `CategoriesViewModel` + `SheetsService` for "Categories" sheet.
- **Bootstrap:** On first run, `AppState.bootstrapIfNeeded` creates spreadsheet (with "Categories" and "Items" sheets and headers) and "MyStuff Photos" folder, saves IDs to UserDefaults.

## Conventions

- ViewModels are `@MainActor` and `ObservableObject`; they hold `@Published` state and call services (which are not actors).
- Services are plain classes; they take a `tokenProvider: () async throws -> String` (or similar) and do not hold UI state.
- Models (`Item`, `Category`) define `columnOrder` and parsing so Sheets rows stay in sync with the app (see [docs/DATA_SCHEMA.md](docs/DATA_SCHEMA.md)).

## Dependencies

- **Google Sign-In:** [GoogleSignIn-iOS](https://github.com/google/GoogleSignIn-iOS) (GoogleSignIn + GoogleSignInSwift). Used for OAuth and token. Bundle ID must match OAuth client: `com.mystuff.inventory`.
