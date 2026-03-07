import SwiftUI

enum ThumbnailSize: String, CaseIterable {
    case compact = "Compact"
    case medium = "Medium"
    case large = "Large"

    var icon: String {
        switch self {
        case .compact: return "square.grid.3x3"
        case .medium: return "square.grid.2x2"
        case .large: return "rectangle.grid.1x2"
        }
    }

    var gridMinimum: CGFloat {
        switch self {
        case .compact: return 80
        case .medium: return 140
        case .large: return 200
        }
    }

    /// Fixed size of the thumbnail image container (width and height).
    var thumbnailDimension: CGFloat {
        gridMinimum
    }
}

struct CategorySection: Identifiable {
    let id: String
    let name: String
    let items: [Item]
    let totalValue: Double
}

enum ItemSortOption: String, CaseIterable {
    case name = "Name"
    case price = "Price"
    case purchaseDate = "Date"

    var icon: String {
        switch self {
        case .name: return "textformat"
        case .price: return "tag"
        case .purchaseDate: return "calendar"
        }
    }
}

struct ItemSortOrder {
    var option: ItemSortOption
    var ascending: Bool
}

struct GalleryView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService
    @AppStorage("thumbnailSize") private var thumbnailSizeRaw: String = ThumbnailSize.medium.rawValue
    @State private var selectedItem: Item?
    @State private var showAddItem = false
    /// Per-category section search text (key = category section id); filters items within that section.
    @State private var sectionSearchTexts: [String: String] = [:]
    /// Per-category sort (key = category section id). When viewing a single category, that category id is used.
    @State private var sectionSortOrders: [String: ItemSortOrder] = [:]

    private var thumbnailSize: ThumbnailSize {
        ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium
    }

    private var inventory: InventoryViewModel { session.inventory }
    private var categories: [Category] { session.categories.categories }

    /// Display name for the current category (for title and dropdown).
    private var currentCategoryName: String {
        guard let id = inventory.selectedCategoryId, !id.isEmpty else { return "All" }
        return categories.first(where: { $0.id == id })?.name ?? "All"
    }

    /// Toolbar title: "N Items" when All, "N Items in [CATEGORY]" when a category is selected.
    private var toolbarTitle: String {
        let n = inventory.filteredItems.count
        guard let id = inventory.selectedCategoryId, !id.isEmpty else {
            return "\(n) Items"
        }
        return "\(n) Items in \(currentCategoryName)"
    }

    /// Total worth (price × quantity) of items in the current filtered view.
    private var totalWorth: Double {
        inventory.filteredItems.reduce(0) { sum, item in
            let p = Double(item.price.trimmingCharacters(in: .whitespaces)) ?? 0
            return sum + p * Double(item.quantity)
        }
    }

    /// When filter is "All", groups filtered items by category for subsectioned layout.
    private var categorySections: [CategorySection] {
        let list = inventory.filteredItems
        let byCategory = Dictionary(grouping: list, by: { $0.categoryId })
        var sections: [CategorySection] = []
        let sortedCats = categories.sorted { $0.order < $1.order }
        for cat in sortedCats {
            guard let items = byCategory[cat.id], !items.isEmpty else { continue }
            let total = items.reduce(0.0) { sum, item in
                let p = Double(item.price.trimmingCharacters(in: .whitespaces)) ?? 0
                return sum + p * Double(item.quantity)
            }
            sections.append(CategorySection(id: cat.id, name: cat.name, items: items, totalValue: total))
        }
        if let uncategorized = byCategory[""], !uncategorized.isEmpty {
            let total = uncategorized.reduce(0.0) { sum, item in
                let p = Double(item.price.trimmingCharacters(in: .whitespaces)) ?? 0
                return sum + p * Double(item.quantity)
            }
            sections.append(CategorySection(id: "", name: "Uncategorized", items: uncategorized, totalValue: total))
        }
        return sections
    }

    private var isShowingAllCategories: Bool {
        guard let id = inventory.selectedCategoryId else { return true }
        return id.isEmpty
    }

    private func sortOrder(forSectionId sectionId: String) -> ItemSortOrder {
        sectionSortOrders[sectionId] ?? ItemSortOrder(option: .name, ascending: true)
    }

    private func sortedItems(_ items: [Item], sectionId: String) -> [Item] {
        let order = sortOrder(forSectionId: sectionId)
        return items.sorted { a, b in
            let cmp: Bool
            switch order.option {
            case .name:
                cmp = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .price:
                let pa = Double(a.price.trimmingCharacters(in: .whitespaces)) ?? 0
                let pb = Double(b.price.trimmingCharacters(in: .whitespaces)) ?? 0
                cmp = pa < pb
            case .purchaseDate:
                cmp = a.purchaseDate.compare(b.purchaseDate, options: .numeric) == .orderedAscending
            }
            return order.ascending ? cmp : !cmp
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
                            if isShowingAllCategories && !categorySections.isEmpty {
                                ForEach(categorySections) { section in
                                    let searchText = sectionSearchTexts[section.id] ?? ""
                                    let filteredItems = searchText.isEmpty
                                        ? section.items
                                        : section.items.filter {
                                            let q = searchText.lowercased()
                                            return $0.name.lowercased().contains(q)
                                                || $0.description.lowercased().contains(q)
                                                || $0.tags.contains { $0.lowercased().contains(q) }
                                        }
                                    let sortedItemsForSection = sortedItems(filteredItems, sectionId: section.id)
                                    let filteredTotal = sortedItemsForSection.reduce(0.0) { sum, item in
                                        let p = Double(item.price.trimmingCharacters(in: .whitespaces)) ?? 0
                                        return sum + p * Double(item.quantity)
                                    }
                                    Section {
                                        if sortedItemsForSection.isEmpty {
                                            Text("No items match your filter")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 32)
                                        } else {
                                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                                ForEach(sortedItemsForSection) { item in
                                                    ItemCardWithHoverPopover(
                                                        item: item,
                                                        categoryName: section.name,
                                                        drive: session.drive,
                                                        thumbnailSize: thumbnailSize,
                                                        onTap: { selectedItem = item }
                                                    )
                                                }
                                            }
                                            .padding(.horizontal)
                                            .padding(.bottom, 24)
                                        }
                                    } header: {
                                        CategorySectionHeader(
                                            name: section.name,
                                            itemCount: sortedItemsForSection.count,
                                            totalValue: filteredTotal,
                                            sectionSearchText: Binding(
                                                get: { sectionSearchTexts[section.id] ?? "" },
                                                set: { sectionSearchTexts[section.id] = $0 }
                                            ),
                                            sortOrder: Binding(
                                                get: { sortOrder(forSectionId: section.id) },
                                                set: { sectionSortOrders[section.id] = $0 }
                                            ),
                                            onAddItem: {
                                                inventory.lastNewItemCategoryId = section.id
                                                showAddItem = true
                                            }
                                        )
                                    }
                                }
                                .padding(.top, 8)
                            } else {
                                let singleCategoryId = inventory.selectedCategoryId ?? ""
                                let singleCategorySorted = sortedItems(inventory.filteredItems, sectionId: singleCategoryId)
                                VStack(spacing: 0) {
                                    CategorySectionHeader(
                                        name: currentCategoryName,
                                        itemCount: singleCategorySorted.count,
                                        totalValue: totalWorth,
                                        sectionSearchText: .constant(""),
                                        sortOrder: Binding(
                                            get: { sortOrder(forSectionId: singleCategoryId) },
                                            set: { sectionSortOrders[singleCategoryId] = $0 }
                                        ),
                                        onAddItem: {
                                            inventory.lastNewItemCategoryId = singleCategoryId
                                            showAddItem = true
                                        },
                                        showSearchField: false
                                    )
                                    LazyVGrid(columns: gridColumns, spacing: 16) {
                                        ForEach(singleCategorySorted) { item in
                                            ItemCardWithHoverPopover(
                                                item: item,
                                                categoryName: currentCategoryName,
                                                drive: session.drive,
                                                thumbnailSize: thumbnailSize,
                                                onTap: { selectedItem = item }
                                            )
                                        }
                                    }
                                    .padding()
                                }
                            }
                        }
                        .refreshable { await inventory.refresh() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                StatusBar(totalWorth: totalWorth, itemCount: inventory.filteredItems.count)
            }
            #if os(iOS)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            #else
            .navigationTitle(toolbarTitle)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Text(toolbarTitle)
                        .font(.headline)
                }
                #endif
                ToolbarItem(placement: .cancellationAction) {
                    Button { showAddItem = true } label: { Image(systemName: "plus") }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("Thumbnail size", selection: $thumbnailSizeRaw) {
                        ForEach(ThumbnailSize.allCases, id: \.rawValue) { size in
                            Image(systemName: size.icon).tag(size.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Category", selection: Binding(get: { inventory.selectedCategoryId }, set: { inventory.selectedCategoryId = $0 })) {
                        Text("All").tag(nil as String?)
                        ForEach(categories) { cat in
                            Text(cat.name).tag(cat.id as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    HStack(spacing: 16) {
                        TextField("Search items", text: Binding(get: { inventory.searchText }, set: { inventory.searchText = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 120, maxWidth: 200)
                            #if os(iOS)
                            .focusEffectDisabled()
                            #endif
                        Rectangle()
                            .fill(.tertiary)
                            .frame(width: 1, height: 20)
                        UserAvatarMenuView()
                    }
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

// MARK: - Hover popover (macOS)

/// Compact popover content showing all item fields after 1s hover.
struct ItemHoverPopoverContent: View {
    let item: Item
    let categoryName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.name)
                .font(.headline)
                .lineLimit(2)
            if !item.description.isEmpty {
                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Divider()
            LabeledRow(label: "Category", value: categoryName)
            LabeledRow(label: "Price", value: Item.priceInNIS(item.price))
            LabeledRow(label: "Quantity", value: "\(item.quantity)")
            LabeledRow(label: "Purchase date", value: item.purchaseDate.isEmpty ? "—" : item.purchaseDate)
            LabeledRow(label: "Condition", value: item.condition.isEmpty ? "—" : item.condition)
            if !item.tags.isEmpty {
                LabeledRow(label: "Tags", value: item.tags.joined(separator: ", "))
            }
            if !item.webLink.isEmpty {
                LabeledRow(label: "Link", value: item.webLink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .frame(minWidth: 220, maxWidth: 320, alignment: .leading)
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
        }
    }
}

/// Wraps an item card and shows a popover with full item info after hovering for 1 second (macOS only).
struct ItemCardWithHoverPopover: View {
    let item: Item
    let categoryName: String
    let drive: DriveService
    var thumbnailSize: ThumbnailSize = .medium
    var onTap: () -> Void

    #if os(macOS)
    @State private var isHovering = false
    @State private var showHoverPopover = false
    @State private var hoverTask: Task<Void, Never>?
    #endif

    var body: some View {
        ItemCard(item: item, drive: drive, photoId: item.photoIds.first, thumbnailSize: thumbnailSize)
            .onTapGesture { onTap() }
            #if os(macOS)
            .onHover { inside in
                isHovering = inside
                if inside {
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run { showHoverPopover = true }
                    }
                } else {
                    hoverTask?.cancel()
                    hoverTask = nil
                    showHoverPopover = false
                }
            }
            .popover(isPresented: $showHoverPopover, arrowEdge: .bottom) {
                ItemHoverPopoverContent(item: item, categoryName: categoryName)
            }
            #endif
    }
}

// MARK: - Item card

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

    private var thumbDimension: CGFloat { thumbnailSize.thumbnailDimension }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: thumbnailSize == .compact ? 8 : 12)
                    .fill(Color.gray.opacity(0.2))
                if let fileId = photoId {
                    DriveImageView(drive: drive, fileId: fileId, contentMode: .fill)
                        .frame(width: thumbDimension, height: thumbDimension)
                        .clipped()
                        .cornerRadius(thumbnailSize == .compact ? 8 : 12)
                } else {
                    Image(systemName: "photo")
                        .font(iconFont)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: thumbDimension, height: thumbDimension)
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

struct CategorySectionHeader: View {
    let name: String
    let itemCount: Int
    let totalValue: Double
    @Binding var sectionSearchText: String
    @Binding var sortOrder: ItemSortOrder
    var onAddItem: (() -> Void)? = nil
    var showSearchField: Bool = true

    private var formattedValue: String {
        if totalValue == 0 { return "₪ 0" }
        return String(format: "₪ %.2f", totalValue)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
            Text("\(itemCount) item(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("·")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("Total: \(formattedValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text("Sort:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ItemSortOption.allCases, id: \.rawValue) { option in
                    let isSelected = sortOrder.option == option
                    Button {
                        if isSelected {
                            sortOrder.ascending.toggle()
                        } else {
                            sortOrder = ItemSortOrder(option: option, ascending: true)
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: option.icon)
                            Text(option.rawValue)
                                .font(.caption2)
                            if isSelected {
                                Image(systemName: sortOrder.ascending ? "arrow.up" : "arrow.down")
                                    .font(.caption2)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 8)
            if let onAddItem {
                Button {
                    onAddItem()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
            if showSearchField {
                TextField("Filter in \(name)", text: $sectionSearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 100, maxWidth: 180)
                #if os(iOS)
                .focusEffectDisabled()
                #endif
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        #if os(iOS)
        .overlay(alignment: .top) { Divider() }
        #endif
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
