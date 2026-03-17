import Foundation

@MainActor
final class AmazonCSVImportViewModel: ObservableObject {
    struct ImportedAmazonItemRow: Identifiable {
        let id = UUID()
        var isSelected: Bool = true

        // Raw reference data
        var asin: String
        var orderId: String
        var website: String

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

