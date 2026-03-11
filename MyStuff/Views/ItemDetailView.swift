import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    let item: Item
    /// Called when the user taps Done or after a successful Delete so the parent can clear the sheet binding.
    var onDismiss: (() -> Void)? = nil
    @State private var isEditing = false
    @State private var currentItem: Item
    @State private var showDeleteConfirmation = false
    @State private var currentStorePrice: String?
    @State private var currentPriceLoading = false
    @State private var currentPriceError: String?
    @State private var selectedAttachment: ItemAttachment?

    init(item: Item, onDismiss: (() -> Void)? = nil) {
        self.item = item
        self.onDismiss = onDismiss
        _currentItem = State(initialValue: item)
    }

    private var inventory: InventoryViewModel { session.inventory }
    private var itemAttachments: [ItemAttachment] { session.attachments.attachments(for: currentItem.id) }
    private var categoryName: String {
        session.categories.categories.first { $0.id == currentItem.categoryId }?.name ?? "—"
    }
    private var locationName: String {
        guard !currentItem.locationId.isEmpty else { return "—" }
        return session.locations.locations.first { $0.id == currentItem.locationId }?.name ?? "—"
    }

    private var isWishlist: Bool { Category.isWishlist(categoryName) }
    private var webLinkURL: URL? {
        let s = currentItem.webLink.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, let u = URL(string: s), u.scheme == "https" || u.scheme == "http" else { return nil }
        return u
    }

    private func dismissSheet() {
        onDismiss?()
        dismiss()
    }

    private static let modeTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )
    private static let editTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity)
    )

    var body: some View {
        Group {
            if isEditing {
                ItemFormView(
                    mode: .edit(currentItem),
                    onSaveSuccess: { updated in
                        withAnimation(.easeInOut(duration: 0.35)) {
                            currentItem = updated
                            isEditing = false
                        }
                        Task { await inventory.refresh() }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.35)) { isEditing = false }
                    }
                )
                .transition(Self.editTransition)
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let fileId = currentItem.photoIds.first {
                                DriveImageView(drive: session.drive, fileId: fileId, contentMode: .fit)
                                    .frame(maxHeight: 280)
                                    .clipped()
                                    .cornerRadius(12)
                            }
                            detailRow("Name", currentItem.name)
                            detailRow("Description", currentItem.description.isEmpty ? "—" : currentItem.description)
                            detailRow("Category", categoryName)
                            if !isWishlist {
                                detailRow("Location", locationName)
                            }
                            priceSection
                            if !isWishlist {
                                detailRow("Quantity", "\(currentItem.quantity)")
                                detailRow("Purchase date", currentItem.purchaseDate.isEmpty ? "—" : currentItem.purchaseDate)
                            }
                            if !currentItem.tags.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Tags")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TagChipsView(tags: currentItem.tags)
                                }
                            }
                            documentsSection
                        }
                        .padding()
                    }
                    .task(id: currentItem.webLink) {
                        await fetchCurrentStorePriceIfNeeded()
                    }
                    .navigationTitle(currentItem.name)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Edit") {
                                withAnimation(.easeInOut(duration: 0.35)) { isEditing = true }
                            }
                            .help("Edit item")
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { dismissSheet() }
                                .help("Done")
                        }
                        ToolbarItem(placement: .destructiveAction) {
                            Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                                .help("Delete item")
                        }
                    }
                    .confirmationDialog("Delete item?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                        Button("Delete \"\(currentItem.name.count > 75 ? String(currentItem.name.prefix(75)) + "…" : currentItem.name)\"", role: .destructive) {
                            Task {
                                await inventory.deleteItems(ids: [currentItem.id])
                                dismissSheet()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This cannot be undone. The item will be removed from your inventory.")
                    }
                    .sheet(item: $selectedAttachment) { att in
                        DocumentPreviewView(
                            drive: session.drive,
                            driveFileId: att.driveFileId,
                            itemName: currentItem.name,
                            documentType: att.kind.displayTitle,
                            driveWebViewURL: URL(string: "https://drive.google.com/file/d/\(att.driveFileId)/view")!,
                            onDismiss: { selectedAttachment = nil }
                        )
                    }
                }
                .transition(Self.modeTransition)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isEditing)
        #if os(iOS)
        .presentationDetents([.large])
        #endif
    }

    @ViewBuilder
    private var priceSection: some View {
        if isWishlist {
            VStack(alignment: .leading, spacing: 4) {
                Text("Price")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Item.formattedPrice(price: currentItem.price, priceCurrency: currentItem.priceCurrency, isWishlist: true))
                    .font(.body)
                currentStorePriceLine
            }
        } else {
            detailRow("Price", Item.formattedPrice(price: currentItem.price, priceCurrency: currentItem.priceCurrency, isWishlist: false))
        }
    }

    @ViewBuilder
    private var currentStorePriceLine: some View {
        if !isWishlist { EmptyView() }
        else if currentItem.webLink.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Add a product URL in Edit to see current store price.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if webLinkURL == nil {
            Text("Current price: — (invalid URL)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if currentPriceLoading {
            Text("Checking price…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let error = currentPriceError {
            Text("Current price: —")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(error)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else if let current = currentStorePrice, !current.isEmpty {
            let formatted = Item.formattedPrice(price: current, priceCurrency: currentItem.priceCurrency, isWishlist: true)
            let trend = Item.priceTrend(entered: currentItem.price, current: current)
            HStack(spacing: 6) {
                Text("Current on store: \(formatted)")
                    .font(.caption)
                    .foregroundStyle(trend == .higher ? .red : (trend == .lower ? .green : .secondary))
                if trend != .same {
                    Image(systemName: trend == .higher ? "arrow.up" : "arrow.down")
                        .font(.caption2)
                        .foregroundStyle(trend == .higher ? .red : .green)
                }
            }
        } else {
            Text("Current price: —")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func fetchCurrentStorePriceIfNeeded() async {
        guard isWishlist, let url = webLinkURL else {
            await MainActor.run {
                currentStorePrice = nil
                currentPriceError = nil
                currentPriceLoading = false
            }
            return
        }
        await MainActor.run {
            currentPriceLoading = true
            currentStorePrice = nil
            currentPriceError = nil
        }
        let price = await session.fetchAndCacheStorePrice(for: url)
        await MainActor.run {
            currentPriceLoading = false
            if let p = price, !p.isEmpty {
                currentStorePrice = p
                currentPriceError = nil
            } else {
                currentStorePrice = nil
                currentPriceError = nil
            }
        }
    }

    @ViewBuilder
    private var documentsSection: some View {
        if !itemAttachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Documents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(itemAttachments) { att in
                        Button {
                            selectedAttachment = att
                        } label: {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(att.displayName.isEmpty ? "Document" : att.displayName)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(att.kind.displayTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }
}
