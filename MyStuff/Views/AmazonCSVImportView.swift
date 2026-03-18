#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AmazonCSVImportViewModel: ObservableObject {
    struct ImportedAmazonItemRow: Identifiable {
        let id = UUID()
        var isSelected: Bool = true

        // Raw reference data
        var asin: String
        var orderId: String
        var website: String

        /// Thumbnail URL derived from the ASIN for Amazon image preview in the import UI only.
        var thumbnailURL: URL?

        // User-editable fields
        var name: String
        var detailDescription: String
        var price: String
        var quantity: Int
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
        rows.filter { row in
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

                let quantityString = value("Original Quantity", in: columns)
                let quantity = Int(quantityString.trimmingCharacters(in: .whitespaces)) ?? 1

                let unitPrice = value("Unit Price", in: columns)
                let currency = value("Currency", in: columns)
                let orderDateString = value("Order Date", in: columns)
                let orderId = value("Order ID", in: columns)
                let asin = value("ASIN", in: columns)
                let website = value("Website", in: columns)

            let trimmedASIN = asin.trimmingCharacters(in: .whitespacesAndNewlines)
            let thumbnailURL: URL?
            if !trimmedASIN.isEmpty {
                thumbnailURL = URL(string: "https://images-na.ssl-images-amazon.com/images/P/\(trimmedASIN).jpg")
            } else {
                thumbnailURL = nil
            }

            let purchaseDate: Date?
            if !orderDateString.isEmpty {
                purchaseDate = isoFormatter.date(from: orderDateString)
            } else {
                purchaseDate = nil
            }

            let row = ImportedAmazonItemRow(
                asin: asin,
                orderId: orderId,
                website: website,
                thumbnailURL: thumbnailURL,
                name: productName,
                detailDescription: productName,
                price: unitPrice,
                quantity: max(1, quantity),
                purchaseDate: purchaseDate,
                categoryId: nil,
                locationId: nil,
                currency: currency
            )
                imported.append(row)
            }

            rows = imported
            selectedYear = nil
            searchText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importSelectedItems() async {
        let selected = rows.filter { $0.isSelected }
        guard !selected.isEmpty else { return }

        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        let dateFormatter = ISO8601DateFormatter()
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
            item.quantity = max(1, row.quantity)
            item.priceCurrency = row.currency
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
        .frame(minWidth: 900, minHeight: 500)
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
                    TableColumn("Thumbnail") { row in
                        if let url = row.thumbnailURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 48, height: 48)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 48)
                                        .clipped()
                                        .cornerRadius(6)
                                case .failure:
                                    Image(systemName: "photo")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 48, height: 48)
                                @unknown default:
                                    Image(systemName: "photo")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 48, height: 48)
                                }
                            }
                        } else {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 48, height: 48)
                        }
                    }
                    TableColumn("Import") { row in
                        Toggle(isOn: binding(for: row).isSelected) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                    TableColumn("Name") { row in
                        TextField("Name", text: binding(for: row).name)
                    }
                    TableColumn("Description") { row in
                        TextField("Description", text: binding(for: row).detailDescription)
                    }
                    TableColumn("Price") { row in
                        TextField("Price", text: binding(for: row).price)
                            .frame(maxWidth: 80)
                    }
                    TableColumn("Qty") { row in
                        Stepper(value: binding(for: row).quantity, in: 1...999) {
                            Text("\(binding(for: row).quantity.wrappedValue)")
                        }
                    }
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
        return $viewModel.rows[index]
    }
}

#endif

