import SwiftUI

enum ThumbnailSize: String, CaseIterable {
    case compact = "Compact"
    case medium = "Medium"
    case large = "Large"

    var gridMinimum: CGFloat {
        switch self {
        case .compact: return 80
        case .medium: return 140
        case .large: return 200
        }
    }
}

struct GalleryView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService
    @AppStorage("thumbnailSize") private var thumbnailSizeRaw: String = ThumbnailSize.medium.rawValue
    @State private var selectedItem: Item?
    @State private var showAddItem = false

    private var thumbnailSize: ThumbnailSize {
        ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium
    }

    private var inventory: InventoryViewModel { session.inventory }
    private var categories: [Category] { session.categories.categories }

    /// Total worth (price × quantity) of items in the current filtered view.
    private var totalWorth: Double {
        inventory.filteredItems.reduce(0) { sum, item in
            let p = Double(item.price.trimmingCharacters(in: .whitespaces)) ?? 0
            return sum + p * Double(item.quantity)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                                    ItemCard(item: item, drive: session.drive, photoId: item.photoIds.first, thumbnailSize: thumbnailSize)
                                        .onTapGesture { selectedItem = item }
                                }
                            }
                            .padding()
                        }
                        .refreshable { await inventory.refresh() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                StatusBar(totalWorth: totalWorth, itemCount: inventory.filteredItems.count)
            }
            .searchable(text: Binding(get: { inventory.searchText }, set: { inventory.searchText = $0 }), prompt: "Search items")
            .navigationTitle("Items")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out") { authService.signOut() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Thumbnail size", selection: $thumbnailSizeRaw) {
                            ForEach(ThumbnailSize.allCases, id: \.rawValue) { size in
                                Text(size.rawValue).tag(size.rawValue)
                            }
                        }
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
        [GridItem(.adaptive(minimum: thumbnailSize.gridMinimum), spacing: 16)]
    }
}

struct ItemCard: View {
    let item: Item
    let drive: DriveService
    let photoId: String?
    var thumbnailSize: ThumbnailSize = .medium

    private var titleFont: Font {
        switch thumbnailSize {
        case .compact: return .caption
        case .medium: return .subheadline
        case .large: return .body
        }
    }

    private var priceFont: Font {
        switch thumbnailSize {
        case .compact: return .caption2
        case .medium, .large: return .caption
        }
    }

    private var iconFont: Font {
        switch thumbnailSize {
        case .compact: return .title2
        case .medium: return .largeTitle
        case .large: return .system(size: 44)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: thumbnailSize == .compact ? 8 : 12)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(1, contentMode: .fit)
                if let fileId = photoId {
                    DriveImageView(drive: drive, fileId: fileId, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .cornerRadius(thumbnailSize == .compact ? 8 : 12)
                } else {
                    Image(systemName: "photo")
                        .font(iconFont)
                        .foregroundStyle(.secondary)
                }
            }
            Text(item.name)
                .font(titleFont)
                .fontWeight(.medium)
                .lineLimit(1)
            HStack(spacing: 4) {
                if !item.price.isEmpty {
                    Text(Item.priceInNIS(item.price))
                        .font(priceFont)
                        .foregroundStyle(.secondary)
                }
                if item.quantity > 1 {
                    Text("× \(item.quantity)")
                        .font(priceFont)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusBar: View {
    let totalWorth: Double
    let itemCount: Int

    private var formattedWorth: String {
        if totalWorth == 0 { return "₪ 0" }
        return String(format: "₪ %.2f", totalWorth)
    }

    var body: some View {
        HStack {
            Text("\(itemCount) item(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Total worth: \(formattedWorth)")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        #if os(iOS)
        .overlay(alignment: .top) { Divider() }
        #endif
    }
}
