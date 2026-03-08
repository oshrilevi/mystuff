import Foundation

/// Produces export data (CSV, PDF) from inventory data. No UI; call from ViewModels or Views.
enum ExportService {

    // MARK: - CSV

    /// Full list of all items, sorted by category (order/name) then item name. Header row + one row per item. CSV-escaped.
    static func makeCSVData(
        items: [Item],
        categories: [Category],
        locations: [Location]
    ) -> Data {
        let sorted = sortItemsByCategoryThenName(items: items, categories: categories)
        let header = [
            "id", "name", "description", "categoryId", "categoryName", "price", "purchaseDate",
            "condition", "quantity", "createdAt", "updatedAt", "photoIds", "webLink", "tags",
            "locationId", "locationName"
        ]
        var rows: [[String]] = [header]
        for item in sorted {
            let catName = categories.first(where: { $0.id == item.categoryId })?.name ?? ""
            let locName = locations.first(where: { $0.id == item.locationId })?.name ?? ""
            rows.append([
                item.id,
                item.name,
                item.description,
                item.categoryId,
                catName,
                item.price,
                item.purchaseDate,
                item.condition,
                String(item.quantity),
                item.createdAt,
                item.updatedAt,
                item.photoIds.joined(separator: ","),
                item.webLink,
                item.tags.joined(separator: ","),
                item.locationId,
                locName
            ])
        }
        let csv = rows.map { row in
            row.map { escapeCSVField($0) }.joined(separator: ",")
        }.joined(separator: "\n")
        return Data(csv.utf8)
    }

    private static func escapeCSVField(_ field: String) -> String {
        let needsQuotes = field.contains(",") || field.contains("\n") || field.contains("\"")
        if !needsQuotes { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - PDF

    /// One page per item, sorted by category then name. Uses SwiftUI ImageRenderer for correct layout (no overlapping text or cut-off images). Async due to thumbnail fetch.
    static func makePDFData(
        items: [Item],
        categories: [Category],
        locations: [Location],
        drive: DriveService
    ) async -> Data {
        let sorted = sortItemsByCategoryThenName(items: items, categories: categories)
        var thumbnailCache: [String: Data] = [:]
        for item in sorted {
            guard let fileId = item.photoIds.first else { continue }
            if thumbnailCache[fileId] != nil { continue }
            if let data = try? await drive.fetchImageData(fileId: fileId) {
                thumbnailCache[fileId] = data
            }
        }
        return await MainActor.run {
            PDFExportBuilder.buildPDF(
                items: sorted,
                categories: categories,
                thumbnailCache: thumbnailCache
            )
        }
    }

    private static func sortItemsByCategoryThenName(
        items: [Item],
        categories: [Category]
    ) -> [Item] {
        func orderKey(_ item: Item) -> (Int, String, String) {
            let cat = categories.first(where: { $0.id == item.categoryId })
            let order = cat?.order ?? Int.max
            let catName = cat?.name ?? ""
            return (order, catName, item.name)
        }
        return items.sorted { orderKey($0) < orderKey($1) }
    }

}
