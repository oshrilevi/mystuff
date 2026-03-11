import SwiftUI
#if os(iOS)
import UIKit

/// On iOS, a toolbar menu to export items as CSV or PDF and share/save via the system share sheet.
struct ExportMenuView: View {
    @EnvironmentObject var session: Session
    @State private var shareItem: ShareableExport?
    @State private var isExportingPDF = false
    @State private var isExportingZIP = false

    var body: some View {
        Menu {
            Button {
                exportCSV()
            } label: {
                Label("Export as CSV", systemImage: "table")
            }
            Button {
                isExportingPDF = true
                Task {
                    await exportPDF()
                    await MainActor.run { isExportingPDF = false }
                }
            } label: {
                Label("Export as PDF", systemImage: "doc.richtext")
            }
            Button {
                isExportingZIP = true
                Task {
                    await exportZIP()
                    await MainActor.run { isExportingZIP = false }
                }
            } label: {
                Label("Export as ZIP", systemImage: "archivebox")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .help("Export items")
        .sheet(item: $shareItem) { item in
            ShareSheetView(activityItems: [item.url])
        }
        .sheet(isPresented: $isExportingPDF) {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Generating PDF…")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $isExportingZIP) {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Preparing ZIP export…")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        shareItem = ShareableExport(url: tempURL)
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
            shareItem = ShareableExport(url: tempURL)
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
                shareItem = ShareableExport(url: zipURL)
            }
        } catch {
            // For now, we silently fail and dismiss the progress view.
            // Future improvement: surface an alert to the user.
        }
    }
}

private struct ShareableExport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
