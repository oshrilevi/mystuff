import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    let item: Item
    @State private var showEdit = false
    @State private var isMovingToWishlist = false

    private var inventory: InventoryViewModel { session.inventory }
    private var wishlist: WishlistViewModel { session.wishlist }
    private var categoryName: String {
        session.categories.categories.first { $0.id == item.categoryId }?.name ?? "—"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let fileId = item.photoIds.first {
                        DriveImageView(drive: session.drive, fileId: fileId, contentMode: .fit)
                            .frame(maxHeight: 280)
                            .clipped()
                            .cornerRadius(12)
                    }
                    detailRow("Name", item.name)
                    detailRow("Description", item.description.isEmpty ? "—" : item.description)
                    detailRow("Category", categoryName)
                    detailRow("Price", Item.priceInNIS(item.price))
                    detailRow("Quantity", "\(item.quantity)")
                    detailRow("Purchase date", item.purchaseDate.isEmpty ? "—" : item.purchaseDate)
                    if !item.tags.isEmpty {
                        detailRow("Tags", item.tags.joined(separator: ", "))
                    }
                    if !item.webLink.isEmpty, let url = URL(string: item.webLink) {
                        Link("View link", destination: url)
                            .font(.body)
                    }
                    Button {
                        Task { await moveToWishlist() }
                    } label: {
                        Label("Move to wish list", systemImage: "heart.circle")
                    }
                    .disabled(isMovingToWishlist)
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle(item.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showEdit = true }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showEdit) {
                ItemFormView(mode: .edit(item))
                    .environmentObject(session)
                    .onDisappear { Task { await inventory.refresh() }; dismiss() }
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

    private func moveToWishlist() async {
        isMovingToWishlist = true
        defer { isMovingToWishlist = false }
        let wishlistItem = WishlistItem(
            name: item.name,
            notes: item.description,
            price: item.price,
            link: item.webLink,
            photoId: item.photoIds.first ?? ""
        )
        await wishlist.add(wishlistItem, imageData: nil)
        if wishlist.errorMessage == nil {
            await inventory.deleteItems(ids: [item.id])
            dismiss()
        }
    }
}
