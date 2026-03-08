import Foundation
import CoreGraphics
import CoreText
import ImageIO
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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

    /// Table of all items sorted by category then name, with thumbnails and key fields. Multi-page. Async due to thumbnail fetch.
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
        return buildPDF(
            items: sorted,
            categories: categories,
            locations: locations,
            thumbnailCache: thumbnailCache
        )
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

    private static func buildPDF(
        items: [Item],
        categories: [Category],
        locations: [Location],
        thumbnailCache: [String: Data]
    ) -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 36
        let thumbnailSize: CGFloat = 44
        let rowHeight: CGFloat = 52
        let headerHeight: CGFloat = 28
        let fontPointSize: CGFloat = 9
        let titleFontSize: CGFloat = 14

        let columns: [(key: String, width: CGFloat)] = [
            ("thumb", thumbnailSize + 8),
            ("name", 100),
            ("category", 70),
            ("price", 44),
            ("date", 72),
            ("condition", 52),
            ("qty", 28),
            ("location", 60),
            ("description", 120)
        ]
        let tableWidth = columns.reduce(0) { $0 + $1.width }
        let contentWidth = min(tableWidth, pageWidth - 2 * margin)
        let scale = contentWidth / tableWidth
        let contentLeft = margin

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return Data() }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        var pageIndex = 0
        var y = pageHeight - margin

        func beginPage() {
            if pageIndex > 0 {
                ctx.endPDFPage()
            }
            ctx.beginPage(mediaBox: &mediaBox)
            pageIndex += 1
            y = pageHeight - margin
        }

        func drawTitle() {
            let title = "MyStuff – Item List"
            drawText(title, at: CGPoint(x: margin, y: y), fontSize: titleFontSize, context: ctx, pageHeight: pageHeight)
            y -= titleFontSize + 8
        }

        beginPage()
        drawTitle()

        // Header row
        let headerY = y
        var colX = contentLeft
        for col in columns {
            if col.key == "thumb" {
                colX += col.width * scale / 2 + 4
            }
            drawText(col.key, at: CGPoint(x: colX, y: headerY), fontSize: fontPointSize, context: ctx, pageHeight: pageHeight)
            colX += col.width * scale
        }
        y -= headerHeight

        for item in items {
            if y < margin + rowHeight {
                beginPage()
            }

            let catName = categories.first(where: { $0.id == item.categoryId })?.name ?? "—"
            let locName = locations.first(where: { $0.id == item.locationId })?.name ?? "—"
            let dateDisplay = item.purchaseDate.isEmpty ? "—" : String(item.purchaseDate.prefix(10))
            let descDisplay = item.description.isEmpty ? "—" : String(item.description.prefix(40))
            if descDisplay.count == 40 { /* already truncated */ }

            colX = contentLeft

            // Thumbnail
            if let fileId = item.photoIds.first, let imgData = thumbnailCache[fileId],
               let cgImage = cgImage(from: imgData) {
                let thumbRect = CGRect(x: colX + 4, y: pageHeight - (y + thumbnailSize), width: thumbnailSize, height: thumbnailSize)
                ctx.saveGState()
                ctx.draw(cgImage, in: thumbRect)
                ctx.restoreGState()
            } else {
                drawText("—", at: CGPoint(x: colX + 8, y: y - 4), fontSize: fontPointSize, context: ctx, pageHeight: pageHeight)
            }
            colX += (columns[0].width) * scale

            // Name, category, price, date, condition, qty, location, description
            let values = [
                String(item.name.prefix(24)),
                String(catName.prefix(12)),
                item.price.isEmpty ? "—" : String(item.price.prefix(8)),
                dateDisplay,
                String(item.condition.prefix(8)),
                String(item.quantity),
                String(locName.prefix(10)),
                descDisplay
            ]
            for (i, val) in values.enumerated() {
                guard i + 1 < columns.count else { break }
                let col = columns[i + 1]
                drawText(val, at: CGPoint(x: colX, y: y - 4), fontSize: fontPointSize, context: ctx, pageHeight: pageHeight)
                colX += col.width * scale
            }

            y -= rowHeight
        }

        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func drawText(
        _ text: String,
        at point: CGPoint,
        fontSize: CGFloat,
        context: CGContext,
        pageHeight: CGFloat
    ) {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        #if os(iOS)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        #else
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        #endif
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let pdfY = pageHeight - point.y - fontSize - 2
        let bounds = CGRect(x: point.x, y: pdfY, width: 400, height: fontSize + 4)
        let path = CGPath(rect: bounds, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        context.saveGState()
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}
