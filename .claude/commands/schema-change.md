Follow this checklist whenever adding or changing a column in any Google Sheets sheet.

## Before you start

Read the relevant files:
- `Models/<ModelName>.swift` — current `columnOrder` and struct properties
- The ViewModel that owns the sheet (e.g. `InventoryViewModel` for Items, `CategoriesViewModel` for Categories)
- `docs/DATA_SCHEMA.md` — current column table for the sheet

## Checklist

- [ ] **Model** (`Models/<Name>.swift`)
  - Add the new property with a sensible default
  - Append the column name to `static let columnOrder` (always append — never insert in the middle)

- [ ] **ViewModel** (the one that owns the sheet)
  - `<name>ToRow` / write path: include the new column value in the correct position
  - `parse<Name>Row` / read path: handle the case where the column doesn't exist yet in old spreadsheets (use `safeIndex` or guard with a default)

- [ ] **Views** — add the field to form, detail, and list row as appropriate

- [ ] **docs/DATA_SCHEMA.md** — add a row to the sheet's column table; update `columnOrder` example if shown

- [ ] **Bootstrap** (`AppState.bootstrapIfNeeded` / `SheetsService.createSpreadsheet`) — if the new column must exist in fresh spreadsheets, add it to the initial header row

- [ ] **CHANGELOG.md** — note the change under "Unreleased"

## Backward compatibility rule

Existing users' spreadsheets will have fewer columns than the new `columnOrder`. The parse function **must** provide a default for any column that may be missing. Pattern:

```swift
let newField = index < row.count ? row[index] : ""
```

Never assume all columns exist when reading.
