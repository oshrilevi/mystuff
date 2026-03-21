Follow this checklist when adding a new major feature that involves a new Google Sheet, ViewModel, and UI screen.

## Before you start

Read:
- `ARCHITECTURE.md` — component roles and data flow
- `Services/Session.swift` — how ViewModels are wired up
- `docs/DATA_SCHEMA.md` — existing sheet schemas for reference patterns
- `docs/DEVELOPMENT.md` — "Where to add things" table

## Checklist

### Data layer

- [ ] **Model** (`Models/<NewThing>.swift`)
  - Struct with `id: String`, timestamps, and relevant fields
  - `static let columnOrder` — column names in sheet order
  - Init with sensible defaults for all optional fields

- [ ] **docs/DATA_SCHEMA.md** — add the new sheet's column table

### ViewModel (`ViewModels/<NewThing>ViewModel.swift`)

- [ ] `@MainActor`, `ObservableObject`, `@Published var items: [NewThing] = []`
- [ ] `load()` — calls `SheetsService.getValues`, parses rows, handles missing sheet (add sheet + header if not present)
- [ ] `add()`, `update()`, `delete()` — append/update/batch-delete rows via `SheetsService`
- [ ] Backward-compatible row parsing (default for missing columns)

### Session wiring (`Services/Session.swift`)

- [ ] Add `let newThings: NewThingViewModel` as a stored property
- [ ] Instantiate in `init(authService:)`: `self.newThings = NewThingViewModel(sheets: self.sheets, appState: self.appState)`
- [ ] Forward `objectWillChange` (follow the existing pattern in Session)
- [ ] Call `await newThings.load()` inside `bootstrap()` after `bootstrapIfNeeded`

### Bootstrap (`Services/AppState.swift` + `Services/SheetsService.swift`)

- [ ] If the sheet must exist for new users: add it to `SheetsService.createSpreadsheet` header creation
- [ ] If existing users should get it lazily: handle in `NewThingViewModel.load()` (add sheet + header if missing — see `LocationsViewModel` as an example)

### UI

- [ ] `Views/<NewThing>View.swift` — main list/grid view
- [ ] `Views/<NewThing>DetailView.swift` or `Views/<NewThing>FormView.swift` as needed
- [ ] **`Views/MainTabView.swift`** — add the new tab/sidebar item

### Documentation

- [ ] **docs/DEVELOPMENT.md** — add a row to the "Where to add things" table
- [ ] **CHANGELOG.md** — note the new feature under "Unreleased"

## Patterns to follow

- See `ListsViewModel` + `ListDetailView` for a clean list-of-items pattern
- See `CombosViewModel` for a parent+children (Combos + ComboItems) pattern
- See `TripsViewModel` for a complex multi-sheet feature (Trips + TripLocations + TripVisits)
- Services are always plain classes (`SheetsService`, `DriveService`) — call them from ViewModels only
