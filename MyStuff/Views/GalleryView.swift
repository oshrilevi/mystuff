import SwiftUI

struct GalleryView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService
    @State private var selectedItem: Item?
    @State private var showAddItem = false

    private var inventory: InventoryViewModel { session.inventory }
    private var categories: [Category] { session.categories.categories }

    var body: some View {
        NavigationStack {
            Group {
                if inventory.isLoading, inventory.items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        if let err = inventory.errorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(8)
                        }
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(inventory.filteredItems) { item in
                                ItemCard(item: item, drive: session.drive, photoId: item.photoIds.first)
                                    .onTapGesture { selectedItem = item }
                            }
                        }
                        .padding()
                    }
                    .refreshable { await inventory.refresh() }
                }
            }
            .searchable(text: Binding(get: { inventory.searchText }, set: { inventory.searchText = $0 }), prompt: "Search items")
            .navigationTitle("Items")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out") { authService.signOut() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Category", selection: Binding(get: { inventory.selectedCategoryId }, set: { inventory.selectedCategoryId = $0 })) {
                            Text("All").tag(nil as String?)
                            ForEach(categories) { cat in
                                Text(cat.name).tag(cat.id as String?)
                            }
                        }
                        Button("Refresh") { Task { await inventory.refresh() } }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddItem = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $selectedItem) { item in
                ItemDetailView(item: item)
                    .environmentObject(session)
            }
            .sheet(isPresented: $showAddItem) {
                ItemFormView(mode: .add)
                    .environmentObject(session)
                    .onDisappear { Task { await inventory.refresh() } }
            }
            .task { await inventory.refresh() }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 140), spacing: 16)]
    }
}

struct ItemCard: View {
    let item: Item
    let drive: DriveService
    let photoId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(1, contentMode: .fit)
                if let fileId = photoId {
                    DriveImageView(drive: drive, fileId: fileId, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .cornerRadius(12)
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            Text(item.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            if !item.price.isEmpty {
                Text(item.price)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
