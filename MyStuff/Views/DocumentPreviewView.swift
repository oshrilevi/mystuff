import SwiftUI
import PDFKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Document content type inferred from file bytes.
private enum DocumentContentType {
    case pdf
    case image
    case unknown
}

private func sniffDocumentType(_ data: Data) -> DocumentContentType {
    guard data.count >= 4 else { return .unknown }
    // PDF: %PDF
    if data.prefix(4).elementsEqual([0x25, 0x50, 0x44, 0x46]) { return .pdf }
    // JPEG: FF D8 FF
    if data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF { return .image }
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if data.prefix(8).elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .image }
    return .unknown
}

/// In-app preview for item documents (PDF or image). Fetches file from Drive, sniffs type, shows PDFView or image with "Open in Drive" and Done.
struct DocumentPreviewView: View {
    let drive: DriveService
    let driveFileId: String
    let itemName: String
    let documentType: String
    let driveWebViewURL: URL
    var onDismiss: () -> Void

    @State private var fileData: Data?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let data = fileData {
                    switch sniffDocumentType(data) {
                    case .pdf:
                        PDFPreviewRepresentable(data: data)
                    case .image:
                        imagePreview(data: data)
                    case .unknown:
                        Text("Unsupported document type.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("\(itemName) - \(documentType)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                        .help("Close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Open in Drive") {
                        #if os(iOS)
                        UIApplication.shared.open(driveWebViewURL)
                        #elseif os(macOS)
                        NSWorkspace.shared.open(driveWebViewURL)
                        #endif
                    }
                    .help("Open in Google Drive")
                }
            }
        }
        .task(id: driveFileId) {
            await loadFile()
        }
    }

    private func loadFile() async {
        isLoading = true
        loadError = nil
        fileData = nil
        do {
            let data = try await drive.fetchFileData(fileId: driveFileId)
            await MainActor.run {
                fileData = data
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    @ViewBuilder
    private func imagePreview(data: Data) -> some View {
        imageFromData(data)
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func imageFromData(_ data: Data) -> some View {
        #if os(iOS)
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
        #elseif os(macOS)
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
        #else
        Image(systemName: "photo")
        #endif
    }
}

// MARK: - PDF preview (PDFKit)

#if os(iOS)
private struct PDFPreviewRepresentable: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = false
        pdfView.displayDirection = .vertical
        if let doc = PDFDocument(data: data) {
            pdfView.document = doc
        }
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        pdfView.document = PDFDocument(data: data)
        applyFitScaleWhenReady(pdfView)
    }

    private func applyFitScaleWhenReady(_ pdfView: PDFView) {
        func apply() {
            pdfView.layoutIfNeeded()
            let b = pdfView.bounds.size
            guard b.width >= 50, b.height >= 50 else { return }
            let fit = pdfView.scaleFactorForSizeToFit
            guard fit > 0 else { return }
            pdfView.scaleFactor = fit
        }
        DispatchQueue.main.async {
            apply()
            DispatchQueue.main.async { apply() }
        }
    }
}
#elseif os(macOS)
private struct PDFPreviewRepresentable: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = false
        pdfView.displayDirection = .vertical
        if let doc = PDFDocument(data: data) {
            pdfView.document = doc
        }
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.document = PDFDocument(data: data)
        applyFitScaleWhenReady(pdfView)
    }

    private func applyFitScaleWhenReady(_ pdfView: PDFView) {
        func apply() {
            pdfView.layoutSubtreeIfNeeded()
            let b = pdfView.bounds.size
            guard b.width >= 50, b.height >= 50 else { return }
            let fit = pdfView.scaleFactorForSizeToFit
            guard fit > 0 else { return }
            pdfView.scaleFactor = fit
        }
        DispatchQueue.main.async {
            apply()
            DispatchQueue.main.async { apply() }
        }
    }
}
#endif
