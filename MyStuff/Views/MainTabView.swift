import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum MainSidebarSelection: Hashable {
    case items
    case lists
    case combos
    case categories
    case locations
    case storesList
    case store(UserStore)
    case sourcesList
    case source(UserSource)
    case youtube
}

struct MainTabView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: MainSidebarSelection = .items
    @State private var itemViewMode: ItemViewMode = .grid
    var body: some View {
        #if os(iOS)
        TabView(selection: $selection) {
            ItemsTabView(viewMode: $itemViewMode)
                .tabItem { Label("My Stuff", systemImage: "square.grid.2x2") }
                .tag(MainSidebarSelection.items)
            CategoriesView()
                .tabItem { Label("Categories", systemImage: "folder") }
                .tag(MainSidebarSelection.categories)
            LocationsView()
                .tabItem { Label("Locations", systemImage: "location") }
                .tag(MainSidebarSelection.locations)
            StoresTabContent()
                .tabItem { Label("Stores", systemImage: "cart") }
                .tag(MainSidebarSelection.storesList)
            SourcesTabContent()
                .tabItem { Label("Sources", systemImage: "link") }
                .tag(MainSidebarSelection.sourcesList)
            YouTubeSearchView()
                .tabItem {
                    Label {
                        Text("YouTube")
                    } icon: {
                        FaviconView(urlString: "https://www.youtube.com", fallbackSystemImage: "play.rectangle", size: 24)
                    }
                }
                .tag(MainSidebarSelection.youtube)
        }
        .onChange(of: session.requestedSidebarSelection) { _, newValue in
            if let sel = newValue {
                selection = sel
                session.requestedSidebarSelection = nil
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await session.prefetchWishlistPricesIfNeeded() }
            }
        }
        #else
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: MainSidebarSelection.items) { Label("My Stuff", systemImage: "square.grid.2x2") }
                NavigationLink(value: MainSidebarSelection.combos) { Label("Combos", systemImage: "square.stack.3d.up") }
                NavigationLink(value: MainSidebarSelection.lists) { Label("My Lists", systemImage: "checklist") }
                Section("Media") {
                    NavigationLink(value: MainSidebarSelection.youtube) {
                        Label {
                            Text("YouTube")
                        } icon: {
                            FaviconView(urlString: "https://www.youtube.com", fallbackSystemImage: "play.rectangle", size: 20)
                        }
                    }
                }
                Section("Stores") {
                    ForEach(session.stores.stores.sorted(by: { $0.order < $1.order })) { store in
                        NavigationLink(value: MainSidebarSelection.store(store)) {
                            Label {
                                Text(store.name)
                            } icon: {
                                StoreIconView(store: store, size: 20)
                            }
                        }
                    }
                }
                Section("Sources") {
                    ForEach(session.sources.sources.sorted(by: { $0.order < $1.order })) { source in
                        NavigationLink(value: MainSidebarSelection.source(source)) {
                            Label {
                                Text(source.name)
                            } icon: {
                                SourceIconView(source: source, size: 20)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    SettingsMenuButton(selection: $selection)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selection {
                case .items:
                    ItemsTabView(viewMode: $itemViewMode)
                case .lists:
                    ListsView()
                case .combos:
                    CombosView()
                case .categories:
                    CategoriesView()
                case .locations:
                    LocationsView()
                case .storesList:
                    StoresView()
                case .store(let store):
                    StoreBrowserView(store: store)
                        .id(store.id)
                case .sourcesList:
                    SourcesView()
                case .source(let source):
                    SourceBrowserView(source: source)
                        .id(source.id)
                case .youtube:
                    YouTubeSearchView()
                }
            }
            .onChange(of: session.requestedSidebarSelection) { _, newValue in
                if let sel = newValue {
                    selection = sel
                    session.requestedSidebarSelection = nil
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await session.prefetchWishlistPricesIfNeeded() }
            }
        }
        #endif
    }
}

#if os(macOS)
private struct SettingsMenuButton: View {
    @Binding var selection: MainSidebarSelection
    @EnvironmentObject var session: Session
    @State private var isExportingPDF = false
    @State private var isExportingZIP = false
    @State private var isImportingAmazonCSV = false
    @State private var isExpanded = false
    @State private var hoveredRow: SettingsRow?

    private enum SettingsRow: Hashable {
        case categories
        case locations
        case stores
        case sources
        case exportCSV
        case exportPDF
        case exportZIP
        case importAmazonCSV
    }

    var body: some View {
        VStack(spacing: 6) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    settingsRowButton(
                        title: "Categories",
                        systemImage: "folder",
                        row: .categories
                    ) {
                        selection = .categories
                    }

                    settingsRowButton(
                        title: "Locations",
                        systemImage: "location",
                        row: .locations
                    ) {
                        selection = .locations
                    }

                    settingsRowButton(
                        title: "Stores",
                        systemImage: "cart",
                        row: .stores
                    ) {
                        selection = .storesList
                    }

                    settingsRowButton(
                        title: "Sources",
                        systemImage: "link",
                        row: .sources
                    ) {
                        selection = .sourcesList
                    }

                    Divider()
                        .padding(.top, 4)

                    Text("Exports")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    settingsRowButton(
                        title: "Export as CSV",
                        systemImage: "table",
                        row: .exportCSV
                    ) {
                        exportCSV()
                    }

                    settingsRowButton(
                        title: "Export as PDF",
                        systemImage: "doc.richtext",
                        row: .exportPDF
                    ) {
                        isExportingPDF = true
                        Task {
                            await exportPDF()
                            await MainActor.run { isExportingPDF = false }
                        }
                    }

                    settingsRowButton(
                        title: "Export as ZIP",
                        systemImage: "archivebox",
                        row: .exportZIP
                    ) {
                        isExportingZIP = true
                        Task {
                            await exportZIP()
                            await MainActor.run { isExportingZIP = false }
                        }
                    }
                    
                    Divider()
                        .padding(.top, 4)

                    Text("Imports")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    settingsRowButton(
                        title: "From Amazon",
                        systemImage: "tray.and.arrow.down",
                        row: .importAmazonCSV
                    ) {
                        isImportingAmazonCSV = true
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                Text("SETTINGS")
                    .font(.callout.weight(.semibold))
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .buttonStyle(.plain)
        .sheet(isPresented: $isExportingPDF) {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Generating PDF…")
                    .font(.headline)
            }
            .frame(width: 200, height: 100)
        }
        .sheet(isPresented: $isExportingZIP) {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Preparing ZIP export…")
                    .font(.headline)
            }
            .frame(width: 220, height: 100)
        }
        .sheet(isPresented: $isImportingAmazonCSV) {
            AmazonCSVImportView(inventoryViewModel: session.inventory)
                .environmentObject(session)
        }
    }

    private func settingsRowButton(
        title: String,
        systemImage: String,
        row: SettingsRow,
        action: @escaping () -> Void
    ) -> some View {
        let isSelected = isRowSelected(row)
        return Button {
            action()
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .frame(width: 16, alignment: .center)
                Text(title)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(highlightColor(for: row))
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredRow = hovering ? row : (hoveredRow == row ? nil : hoveredRow)
        }
    }

    private func highlightColor(for row: SettingsRow) -> Color {
        if isRowSelected(row) {
            return Color.accentColor.opacity(0.18)
        }
        if hoveredRow == row {
            return Color.accentColor.opacity(0.10)
        }
        return .clear
    }

    private func isRowSelected(_ row: SettingsRow) -> Bool {
        switch row {
        case .categories:
            return selection == .categories
        case .locations:
            return selection == .locations
        case .stores:
            return selection == .storesList
        case .sources:
            return selection == .sourcesList
        case .exportCSV, .exportPDF, .exportZIP, .importAmazonCSV:
            return false
        }
    }

    private func exportCSV() {
        let data = ExportService.makeCSVData(
            items: session.inventory.items,
            categories: session.categories.categories,
            locations: session.locations.locations
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mystuff_items.csv")
        try? data.write(to: tempURL)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "mystuff_items.csv"
        panel.begin { response in
            if response == .OK, let dest = panel.url {
                try? FileManager.default.copyItem(at: tempURL, to: dest)
            }
        }
    }

    private func exportPDF() async {
        let data = await ExportService.makePDFData(
            items: session.inventory.items,
            categories: session.categories.categories,
            locations: session.locations.locations,
            drive: session.drive
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mystuff_items.pdf")
        try? data.write(to: tempURL)
        await MainActor.run {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "mystuff_items.pdf"
            panel.begin { response in
                if response == .OK, let dest = panel.url {
                    try? FileManager.default.copyItem(at: tempURL, to: dest)
                }
            }
        }
    }

    private func exportZIP() async {
        do {
            let zipURL = try await ExportService.makeZIPArchiveURL(
                items: session.inventory.items,
                categories: session.categories.categories,
                locations: session.locations.locations,
                attachments: session.attachments.attachments,
                drive: session.drive
            )
            await MainActor.run {
                let fm = FileManager.default
                if let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                    let dest = downloads.appendingPathComponent("MyStuffBackup.zip")
                    // Overwrite any existing backup with the latest export.
                    try? fm.removeItem(at: dest)
                    do {
                        try fm.copyItem(at: zipURL, to: dest)
                        showBackupCompletedToast(destination: dest)
                    } catch {
                        // If copy fails, we silently ignore for now.
                    }
                }
            }
        } catch {
            // Ignore for now; progress sheet will dismiss.
        }
    }

    private func showBackupCompletedToast(destination: URL) {
        #if os(macOS)
        let notification = NSUserNotification()
        notification.title = "MyStuff Backup Complete"
        notification.informativeText = "Saved to Downloads/\(destination.lastPathComponent)"
        NSUserNotificationCenter.default.deliver(notification)
        #endif
    }
}
#endif

#if os(macOS)
@MainActor
final class AmazonCSVImportViewModel: ObservableObject {
    private static let lastCSVPathKey = "mystuff_last_amazon_csv_path"
    struct ImportedAmazonItemRow: Identifiable {
        let id = UUID()
        var isSelected: Bool = false

        // Raw reference data
        var asin: String
        var orderId: String
        var website: String

        // User-editable fields
        var name: String
        var detailDescription: String
        var price: String
        var purchaseDate: Date?
        var categoryId: String?
        var locationId: String?
        var currency: String
    }

    @Published var rows: [ImportedAmazonItemRow] = []
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorMessage: String?

    // Filtering
    @Published var selectedYear: Int?
    @Published var searchText: String = ""

    private let inventoryViewModel: InventoryViewModel

    init(inventoryViewModel: InventoryViewModel) {
        self.inventoryViewModel = inventoryViewModel
    }

    var availableYears: [Int] {
        let years = rows.compactMap { row -> Int? in
            guard let date = row.purchaseDate else { return nil }
            return Calendar.current.component(.year, from: date)
        }
        return Array(Set(years)).sorted()
    }

    var filteredRows: [ImportedAmazonItemRow] {
        let base = rows.filter { row in
            // Year filter
            if let year = selectedYear, let date = row.purchaseDate {
                let rowYear = Calendar.current.component(.year, from: date)
                if rowYear != year {
                    return false
                }
            }

            // Text filter
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                let q = query.lowercased()
                let matchesName = row.name.lowercased().contains(q)
                let matchesDescription = row.detailDescription.lowercased().contains(q)
                if !matchesName && !matchesDescription {
                    return false
                }
            }

            return true
        }

        return base.sorted { lhs, rhs in
            // Default sort: name ascending
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func loadCSV(from url: URL) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                errorMessage = "Could not read CSV as UTF-8 text."
                return
            }

            let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            guard let headerLine = lines.first else {
                errorMessage = "CSV file is empty."
                return
            }

            let headerColumns = parseCSVRow(headerLine)
            let headerIndex: [String: Int] = Dictionary(uniqueKeysWithValues: headerColumns.enumerated().map { ($1, $0) })

            func value(_ key: String, in columns: [String]) -> String {
                guard let idx = headerIndex[key], idx < columns.count else { return "" }
                return columns[idx]
            }

            let isoFormatter = ISO8601DateFormatter()
            let ymdFormatter = DateFormatter()
            ymdFormatter.locale = Locale(identifier: "en_US_POSIX")
            ymdFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            ymdFormatter.dateFormat = "yyyy-MM-dd"

            var imported: [ImportedAmazonItemRow] = []
            for line in lines.dropFirst() {
                let columns = parseCSVRow(line)
                if columns.isEmpty {
                    continue
                }

                let productName = value("Product Name", in: columns)
                if productName.isEmpty {
                    continue
                }

                let unitPrice = value("Unit Price", in: columns)
                let currency = "USD"
                let orderDateString = value("Order Date", in: columns)
                let orderId = value("Order ID", in: columns)
                let asin = value("ASIN", in: columns)
                let website = value("Website", in: columns)

                let trimmedOrderDate = orderDateString.trimmingCharacters(in: .whitespacesAndNewlines)
                let purchaseDate: Date?
                if !trimmedOrderDate.isEmpty {
                    if let d = isoFormatter.date(from: trimmedOrderDate) {
                        purchaseDate = d
                    } else {
                        // Fallback for non-ISO Amazon formats, e.g. "YYYY-MM-DD …"
                        let prefix10 = String(trimmedOrderDate.prefix(10))
                        purchaseDate = ymdFormatter.date(from: prefix10)
                    }
                } else {
                    purchaseDate = nil
                }

                let row = ImportedAmazonItemRow(
                    asin: asin,
                    orderId: orderId,
                    website: website,
                    name: productName,
                    detailDescription: productName,
                    price: unitPrice,
                    purchaseDate: purchaseDate,
                    categoryId: nil,
                    locationId: nil,
                    currency: currency
                )
                imported.append(row)
            }

            rows = imported
            // Remember this CSV for quick re-loading next time.
            UserDefaults.standard.set(url.path, forKey: Self.lastCSVPathKey)
            selectedYear = nil
            searchText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importSelectedItems() async {
        let selected = rows.filter { $0.isSelected }
        guard !selected.isEmpty else { return }

        // Validate categories
        let rowsNeedingCategory = selected.filter { row in
            (row.categoryId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !rowsNeedingCategory.isEmpty {
            errorMessage = "Please select a category for all selected items."
            return
        }

        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let itemsToImport: [Item] = selected.map { row in
            var item = Item()
            item.name = row.name
            item.description = row.detailDescription
            item.categoryId = row.categoryId ?? ""
            item.locationId = row.locationId ?? ""
            item.price = row.price.trimmingCharacters(in: .whitespaces)
            if let date = row.purchaseDate {
                item.purchaseDate = dateFormatter.string(from: date)
            }
            item.condition = "New"
            item.quantity = 1
            item.priceCurrency = "USD"
            return item
        }

        await inventoryViewModel.importItems(itemsToImport)
    }

    // Simple CSV parser that respects quoted fields.
    private func parseCSVRow(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()

        while let ch = iterator.next() {
            if ch == "\"" {
                if inQuotes {
                    if let next = iterator.next() {
                        if next == "\"" {
                            current.append("\"")
                        } else if next == "," {
                            inQuotes = false
                            result.append(current)
                            current = ""
                        } else {
                            inQuotes = false
                            current.append(next)
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if ch == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }
}

@available(macOS 13.0, *)
struct AmazonCSVImportView: View {
    @EnvironmentObject var session: Session
    @StateObject private var viewModel: AmazonCSVImportViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false

    private static let lastCSVPathKey = "mystuff_last_amazon_csv_path"
    private var hasRecentCSV: Bool {
        UserDefaults.standard.string(forKey: Self.lastCSVPathKey) != nil
    }

    // Category hierarchy for the Category picker (matches ItemFormView behavior).
    private var categories: [Category] { session.categories.categories }
    private var wishlistCategoryId: String? {
        categories.first(where: { Category.isWishlist($0.name) })?.id
    }
    private var topLevelCategories: [Category] {
        categories
            .filter { ($0.parentId ?? "").isEmpty }
            .sorted { ($0.order, $0.name.lowercased()) < ($1.order, $1.name.lowercased()) }
    }
    private var childrenByParentId: [String: [Category]] {
        var result: [String: [Category]] = [:]
        for cat in categories {
            guard let pid = cat.parentId, !pid.isEmpty else { continue }
            result[pid, default: []].append(cat)
        }
        for (pid, list) in result {
            result[pid] = list.sorted { ($0.order, $0.name.lowercased()) < ($1.order, $1.name.lowercased()) }
        }
        return result
    }
    private struct CategoryPickerRow: Identifiable {
        let id: String
        let category: Category
        let isChild: Bool
        let indentLevel: Int
        let isSelectable: Bool
    }
    private var categoryPickerRows: [CategoryPickerRow] {
        var rows: [CategoryPickerRow] = []
        for parent in topLevelCategories {
            let children = childrenByParentId[parent.id] ?? []
            let isWishlist = wishlistCategoryId == parent.id

            if children.isEmpty {
                rows.append(
                    CategoryPickerRow(
                        id: parent.id,
                        category: parent,
                        isChild: false,
                        indentLevel: 0,
                        isSelectable: isWishlist
                    )
                )
            } else {
                rows.append(
                    CategoryPickerRow(
                        id: parent.id,
                        category: parent,
                        isChild: false,
                        indentLevel: 0,
                        isSelectable: isWishlist
                    )
                )
                for child in children {
                    rows.append(
                        CategoryPickerRow(
                            id: child.id,
                            category: child,
                            isChild: true,
                            indentLevel: 1,
                            isSelectable: true
                        )
                    )
                }
            }
        }
        return rows
    }

    // Default "Home" location for imported rows.
    private var homeLocationId: String? {
        session.locations.locations.first { $0.name == "Home" }?.id
    }

    init(inventoryViewModel: InventoryViewModel) {
        _viewModel = StateObject(wrappedValue: AmazonCSVImportViewModel(inventoryViewModel: inventoryViewModel))
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            filters
            content
            footer
        }
        .padding()
        .frame(minWidth: 1200, minHeight: 700)
    }

    private var header: some View {
        HStack {
            Text("Import from Amazon CSV")
                .font(.title2.weight(.semibold))
            Spacer()
            Button("Load last CSV…") {
                guard let path = UserDefaults.standard.string(forKey: Self.lastCSVPathKey) else { return }
                let url = URL(fileURLWithPath: path)
                Task {
                    await viewModel.loadCSV(from: url)
                }
            }
            .disabled(!hasRecentCSV)
            Button("Choose CSV…") {
                showFileImporter = true
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .text, .data],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task {
                    await viewModel.loadCSV(from: url)
                }
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker("Year", selection: Binding(
                get: { viewModel.selectedYear ?? -1 },
                set: { newValue in
                    viewModel.selectedYear = newValue == -1 ? nil : newValue
                }
            )) {
                Text("All years").tag(-1)
                ForEach(viewModel.availableYears, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.menu)

            TextField("Search name or description", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)

            Spacer()
        }
    }

    private var content: some View {
        Group {
            if viewModel.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Parsing CSV…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredRows.isEmpty {
                Text("No items to show. Choose an Amazon Order History CSV to begin.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(viewModel.filteredRows) {
                    TableColumn("Import") { row in
                        Toggle(isOn: binding(for: row).isSelected) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                    .width(50)

                    TableColumn("Name") { row in
                        TextField("Name", text: binding(for: row).name)
                    }
                    .width(min: 160, ideal: 260)

                    TableColumn("Description") { row in
                        TextField("Description", text: binding(for: row).detailDescription)
                    }
                    .width(min: 220, ideal: 400)

                    TableColumn("Price") { row in
                        TextField("Price", text: binding(for: row).price)
                            .frame(maxWidth: 80)
                    }
                    .width(80)

                    TableColumn("Category") { row in
                        Picker("Category", selection: Binding(
                            get: { binding(for: row).categoryId.wrappedValue ?? "" },
                            set: { newValue in
                                binding(for: row).categoryId.wrappedValue = newValue.isEmpty ? nil : newValue
                            }
                        )) {
                            Text("—").tag("")
                            ForEach(categoryPickerRows) { pickerRow in
                                let label = pickerRow.indentLevel == 0
                                    ? pickerRow.category.name
                                    : String(repeating: "    ", count: pickerRow.indentLevel) + pickerRow.category.name
                                if pickerRow.isSelectable {
                                    Text(label).tag(pickerRow.category.id)
                                } else {
                                    Text(label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .disabled(true)
                                }
                            }
                        }
                        .labelsHidden()
                    }
                    .width(140)

                    TableColumn("Location") { row in
                        Picker("Location", selection: Binding(
                            get: { binding(for: row).locationId.wrappedValue ?? "" },
                            set: { newValue in
                                binding(for: row).locationId.wrappedValue = newValue.isEmpty ? nil : newValue
                            }
                        )) {
                            Text("—").tag("")
                            ForEach(session.locations.locations, id: \.id) { location in
                                Text(location.name).tag(location.id)
                            }
                        }
                        .labelsHidden()
                    }
                    .width(140)

                    TableColumn("Date") { row in
                        if let date = binding(for: row).purchaseDate.wrappedValue {
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { date },
                                    set: { newDate in
                                        binding(for: row).purchaseDate.wrappedValue = newDate
                                    }
                                ),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(140)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if let message = viewModel.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
            }
            Spacer()
            let selectedCount = viewModel.rows.filter { $0.isSelected }.count
            Text("\(selectedCount) selected")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            Button("Import selected") {
                Task {
                    await viewModel.importSelectedItems()
                    dismiss()
                }
            }
            .disabled(viewModel.rows.allSatisfy { !$0.isSelected })
        }
        .padding(.top, 8)
    }

    private func binding(for row: AmazonCSVImportViewModel.ImportedAmazonItemRow) -> Binding<AmazonCSVImportViewModel.ImportedAmazonItemRow> {
        guard let index = viewModel.rows.firstIndex(where: { $0.id == row.id }) else {
            fatalError("Row not found")
        }
        if viewModel.rows[index].locationId == nil, let homeId = homeLocationId {
            viewModel.rows[index].locationId = homeId
        }
        return $viewModel.rows[index]
    }
}
#endif

#if os(iOS)
/// On iOS, a single "Stores" tab that lists stores and pushes to the browser when one is tapped.
private struct StoresTabContent: View {
    @EnvironmentObject var session: Session

    private var sortedStores: [UserStore] {
        session.stores.stores.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedStores) { store in
                    NavigationLink(value: store) {
                        Label {
                            Text(store.name)
                        } icon: {
                            StoreIconView(store: store, size: 20)
                        }
                    }
                }
            }
            .navigationTitle("Stores")
            .navigationDestination(for: UserStore.self) { store in
                StoreBrowserView(store: store)
                    .id(store.id)
            }
        }
    }
}

/// On iOS, a single "Sources" tab that lists sources and pushes to the browser when one is tapped.
private struct SourcesTabContent: View {
    @EnvironmentObject var session: Session

    private var sortedSources: [UserSource] {
        session.sources.sources.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedSources) { source in
                    NavigationLink(value: source) {
                        Label {
                            Text(source.name)
                        } icon: {
                            SourceIconView(source: source, size: 20)
                        }
                    }
                }
            }
            .navigationTitle("Sources")
            .navigationDestination(for: UserSource.self) { source in
                SourceBrowserView(source: source)
                    .id(source.id)
            }
        }
    }
}
#endif

struct ItemsTabView: View {
    @EnvironmentObject var session: Session
    @Binding var viewMode: ItemViewMode

    var body: some View {
        Group {
            if viewMode == .grid {
                GalleryView(viewMode: $viewMode)
            } else {
                ItemsListView(viewMode: $viewMode)
            }
        }
        .task {
            // Ensure combos are available from app launch so item context menus
            // can show which combos an item belongs to without first visiting Combos.
            await session.combos.ensureLoaded()
            await session.prefetchWishlistPricesIfNeeded()
        }
    }
}
