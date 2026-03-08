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

    init(item: Item, onDismiss: (() -> Void)? = nil) {
        self.item = item
        self.onDismiss = onDismiss
        _currentItem = State(initialValue: item)
    }

    private var inventory: InventoryViewModel { session.inventory }
    private var categoryName: String {
        session.categories.categories.first { $0.id == currentItem.categoryId }?.name ?? "—"
    }
    private var locationName: String {
        guard !currentItem.locationId.isEmpty else { return "—" }
        return session.locations.locations.first { $0.id == currentItem.locationId }?.name ?? "—"
    }

    private var isWishlist: Bool { Category.isWishlist(categoryName) }

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
                            detailRow("Price", Item.priceInNIS(currentItem.price))
                            if !isWishlist {
                                detailRow("Quantity", "\(currentItem.quantity)")
                                detailRow("Purchase date", currentItem.purchaseDate.isEmpty ? "—" : currentItem.purchaseDate)
                            }
                            if !currentItem.tags.isEmpty {
                                detailRow("Tags", currentItem.tags.joined(separator: ", "))
                            }
                            if !currentItem.webLink.isEmpty, let url = URL(string: currentItem.webLink) {
                                Link("View link", destination: url)
                                    .font(.body)
                            }
                        }
                        .padding()
                    }
                    .navigationTitle(currentItem.name)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Edit") {
                                withAnimation(.easeInOut(duration: 0.35)) { isEditing = true }
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { dismissSheet() }
                        }
                        ToolbarItem(placement: .destructiveAction) {
                            Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                        }
                    }
                    .confirmationDialog("Delete item?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                        Button("Delete \"\(currentItem.name)\"", role: .destructive) {
                            Task {
                                await inventory.deleteItems(ids: [currentItem.id])
                                dismissSheet()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This cannot be undone. The item will be removed from your inventory.")
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
