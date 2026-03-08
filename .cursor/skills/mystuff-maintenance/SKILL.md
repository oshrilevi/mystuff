---
name: mystuff-maintenance
description: Follows MyStuff app architecture and docs when modifying the macOS/iPhone inventory app. Use when adding features, changing Item or Category fields, touching Google Sheets/Drive, Session, ViewModels, or bootstrap. Ensures schema and docs stay in sync.
---

# MyStuff Maintenance

When working on the MyStuff codebase (Swift/SwiftUI, Google Sheets + Drive), follow the project docs and conventions below.

## When to use this skill

- Adding or changing **Item** or **Category** fields (new columns, types).
- Adding new tabs, screens, or API calls (Sheets/Drive).
- Changing **bootstrap**, **auth**, or **Session** wiring.
- Fixing or extending **ViewModels**, **Services**, or **Models**.

## Read the docs first

- **Structure and flow:** [ARCHITECTURE.md](../../ARCHITECTURE.md) – entry point, Session, ViewModels, Services, data flow.
- **Where to change code:** [docs/DEVELOPMENT.md](../../docs/DEVELOPMENT.md) – “Where to add things” table, conventions, testing.
- **Sheets/Drive schema:** [docs/DATA_SCHEMA.md](../../docs/DATA_SCHEMA.md) – column indices, sheet names, UserDefaults keys, “Adding or changing columns”.

## Conventions to follow

- **ViewModels:** `@MainActor`, `ObservableObject`; call `SheetsService` / `DriveService`; parsing lives in the ViewModel that owns the sheet (e.g. `InventoryViewModel` for Items).
- **Services:** Plain classes, `tokenProvider`; no UI or ViewModels.
- **Models:** Structs with `columnOrder`; keep in sync with Sheets columns and parsing.

## Adding or changing Item/Category columns

1. Update **Model** (`Models/Item.swift` or `Models/Category.swift`): new property and `columnOrder`.
2. Update **ViewModel**: `itemToRow` / `parseItemRow` (Items) or category row encoding/parsing. For Items, preserve **backward compatibility** in `parseItemRow` for existing spreadsheets with fewer columns (defaults for missing indices).
3. Update **Views**: form, detail, list as needed.
4. Update **docs/DATA_SCHEMA.md**: table and “Adding or changing columns” if applicable.
5. If the new column is required for new spreadsheets, ensure **bootstrap** writes the header (e.g. `SheetsService.createSpreadsheet` for the initial header row).

## After schema or feature changes

- Note **CHANGELOG.md** for releases.
- If columns or sheet layout changed, keep **DATA_SCHEMA.md** accurate.
