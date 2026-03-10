# MyStuff – Data Schema

Reference for the Google Sheets and Drive layout. When you add or reorder columns, update **Models** (`Item.columnOrder` / `Category.columnOrder`), **ViewModels** (row serialization/parsing), and this doc.

## Google Spreadsheet

Created on first run via `SheetsService.createSpreadsheet`. Five sheets:

### Sheet: **Categories**

| Column index | Name   | Type   | Notes                     |
|--------------|--------|--------|---------------------------|
| A (0)        | id     | String | UUID                      |
| B (1)        | name   | String | Display name              |
| C (2)        | order  | Int    | Sort order (row-based)    |
| D (3)        | color  | String | Optional hex (e.g. #FF5733) for category header color |

- Row 1 is the header row (`id`, `name`, `order`, `color`). Data starts at row 2.
- `Category.columnOrder` in code: `["id", "name", "order", "color"]`.

### Sheet: **Items**

| Column index | Name        | Type   | Notes                                      |
|--------------|-------------|--------|--------------------------------------------|
| A (0)        | id          | String | UUID                                       |
| B (1)        | name        | String | Item name                                  |
| C (2)        | description | String | Free text                                  |
| D (3)        | categoryId  | String | FK to Categories id                        |
| E (4)        | price       | String | Stored as string (e.g. "99.00")            |
| F (5)        | purchaseDate| String | ISO8601 or YYYY-MM-DD                      |
| G (6)        | condition   | String | e.g. Item.conditionPresets                 |
| H (7)        | quantity    | Int    | Number of copies (default 1)               |
| I (8)        | createdAt   | String | ISO8601                                    |
| J (9)        | updatedAt   | String | ISO8601                                    |
| K (10)       | photoIds    | String | Comma-separated Drive file IDs             |
| L (11)       | webLink     | String | URL                                        |
| M (12)       | tags        | String | Comma-separated tags                       |
| N (13)       | locationId  | String | FK to Locations id (optional)             |
| O (14)       | priceCurrency | String | For Wishlist only: "NIS", "USD", or empty (NIS). Ignored for other categories. |

- Row 1 is the header row. Data starts at row 2.
- `Item.columnOrder` in code: `["id", "name", "description", "categoryId", "price", "purchaseDate", "condition", "quantity", "createdAt", "updatedAt", "photoIds", "webLink", "tags", "locationId", "priceCurrency"]`.
- **Parsing:** `InventoryViewModel.parseItemRow` supports older spreadsheets with fewer columns (e.g. without quantity, webLink, tags, locationId). New rows are written with the full column set via `itemToRow`.

### Sheet: **Locations**

| Column index | Name   | Type   | Notes                  |
|--------------|--------|--------|------------------------|
| A (0)        | id     | String | UUID                   |
| B (1)        | name   | String | Display name           |
| C (2)        | order  | Int    | Sort order (row-based) |

- Row 1 is the header row (`id`, `name`, `order`). Data starts at row 2.
- `Location.columnOrder` in code: `["id", "name", "order"]`.
- For existing spreadsheets created before Locations existed, the app adds the "Locations" sheet on first load via `SheetsService.addSheet` and appends the header (migration in `LocationsViewModel.load()`).

### Sheet: **Stores**

| Column index | Name      | Type   | Notes                                   |
|--------------|-----------|--------|-----------------------------------------|
| A (0)        | id        | String | UUID                                    |
| B (1)        | name      | String | Display name                            |
| C (2)        | startURL  | String | URL to open in the in-app store browser |
| D (3)        | order     | Int    | Sort order (row-based)                  |
| E (4)        | systemImage | String | SF Symbol name; used as fallback when the store’s favicon (from start URL domain) cannot be loaded |

- Row 1 is the header row (`id`, `name`, `startURL`, `order`, `systemImage`). Data starts at row 2.
- `UserStore.columnOrder` in code: `["id", "name", "startURL", "order", "systemImage"]`.
- For existing spreadsheets created before Stores existed, the app adds the "Stores" sheet on first load via `SheetsService.addSheet` and appends the header (migration in `StoresViewModel.load()`).
- New spreadsheets are seeded with three default stores (Amazon, AliExpress, B&H Photo).

### Sheet: **Sources**

| Column index | Name   | Type   | Notes                                        |
|--------------|--------|--------|----------------------------------------------|
| A (0)        | id     | String | UUID                                         |
| B (1)        | name   | String | Display name                                 |
| C (2)        | url    | String | URL to open in the in-app source browser     |
| D (3)        | order  | Int    | Sort order (row-based)                       |

- Row 1 is the header row (`id`, `name`, `url`, `order`). Data starts at row 2.
- `UserSource.columnOrder` in code: `["id", "name", "url", "order"]`.
- For existing spreadsheets created before Sources existed, the app adds the "Sources" sheet on first load via `SheetsService.addSheet` and appends the header (migration in `SourcesViewModel.load()`). No default seed rows; user adds sources in Settings → Sources.

## Google Drive

- **Folder:** One folder per user, name **"MyStuff Photos"**, created in bootstrap via `DriveService.createFolder`.
- **Files:** Photos are uploaded with a generated filename; the **file ID** is stored in the Items sheet in `photoIds` (comma-separated). No subfolders; all photos live in that single folder.

## Local persistence (UserDefaults)

| Key                         | Purpose                          |
|-----------------------------|----------------------------------|
| `mystuff_spreadsheet_id`    | Current user’s spreadsheet ID    |
| `mystuff_drive_folder_id`  | Current user’s photo folder ID   |
| `mystuff_items_cache`      | Offline cache of items (encoded)  |
| `mystuff_categories_cache` | Offline cache of categories       |
| `mystuff_pinned_category_ids` | Pinned category IDs (Set)     |
| `mystuff_default_location_id` | Default location ID for new items |
| `mystuff_browser_<storeId>`   | Last-visited URL per store (in-app browser); storeId from Stores sheet |
| `mystuff_browser_source_<id>` | Last-visited URL per source (in-app browser); id from Sources sheet   |

**Caches directory (not UserDefaults):**

| Location                    | Purpose                                                                 |
|-----------------------------|-------------------------------------------------------------------------|
| `Caches/MyStuffThumbnails/` | Disk cache for Drive image bytes (item photos). Eviction when total size exceeds 300 MB (oldest files by modification date removed first). In-memory cache (NSCache) also used; no TTL. |

Clearing spreadsheet/folder IDs (e.g. for debugging or “start fresh”) is done via `AppState.clearStoredIds()`.

## Adding or changing columns

1. Update the **Model** (`Item` or `Category`): new property and `columnOrder` array.
2. Update the **ViewModel** that writes/reads that sheet: `itemToRow`/`parseItemRow` or the category equivalent. Preserve backward compatibility in parsing if existing users have old sheets (e.g. default for missing column).
3. Update **DATA_SCHEMA.md** (this file).
4. If the new column is required for new spreadsheets, ensure **bootstrap** writes the new header (e.g. `SheetsService.createSpreadsheet` for the initial header row).
