import SwiftUI
import CoreGraphics
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Renders one item as a full PDF page using SwiftUI layout; used by ImageRenderer for correct text and image placement.
private struct ItemPDFPageView: View {
    let item: Item
    let categoryName: String
    let thumbnailData: Data?

    private var thumbnailImage: Image? {
        guard let data = thumbnailData else { return nil }
        #if os(iOS)
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #else
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            Text(item.name.isEmpty ? "Item" : item.name)
                .font(.title)
                .fontWeight(.semibold)

            if let img = thumbnailImage {
                img
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipped()
            }

            row("Category", categoryName)
            row("Description", item.description.isEmpty ? "—" : item.description)
            row("Price", Item.formattedPrice(price: item.price, priceCurrency: item.priceCurrency, isWishlist: Category.isWishlist(categoryName)))
            row("Purchase date", item.purchaseDate.isEmpty ? "—" : String(item.purchaseDate.prefix(10)))
            row("Quantity", String(item.quantity))

            Spacer(minLength: 0)
        }
        .frame(width: 612, height: 792)
        .padding(.horizontal, 40)
        .padding(.vertical, 56)
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Builds PDF data by rendering one SwiftUI page per item with ImageRenderer (proper layout, no overlap).
enum PDFExportBuilder {
    @MainActor
    static func buildPDF(
        items: [Item],
        categories: [Category],
        thumbnailCache: [String: Data]
    ) -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return Data() }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        if items.isEmpty {
            ctx.beginPage(mediaBox: &mediaBox)
            ctx.endPDFPage()
            ctx.closePDF()
            return data as Data
        }

        for (index, item) in items.enumerated() {
            if index > 0 {
                ctx.endPDFPage()
            }
            ctx.beginPage(mediaBox: &mediaBox)

            let catName = categories.first(where: { $0.id == item.categoryId })?.name ?? "—"
            let thumbData = item.photoIds.first.flatMap { thumbnailCache[$0] }

            let view = ItemPDFPageView(
                item: item,
                categoryName: catName,
                thumbnailData: thumbData
            )
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: pageWidth, height: pageHeight)
            renderer.render { size, draw in
                draw(ctx)
            }
        }

        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }
}
