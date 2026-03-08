import SwiftUI

/// Rounds value to 2 decimal places and formats as currency without trailing zeros.
fileprivate func formatCurrency(_ value: Double) -> String {
    if value == 0 { return "₪ 0" }
    let rounded = (value * 100).rounded() / 100
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    return "₪ \(formatter.string(from: NSNumber(value: rounded)) ?? "0")"
}

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

/// Unified display choice: grid at a thumbnail size, or list. One segmented control in the toolbar.
enum ItemsDisplayChoice: String, CaseIterable {
    case gridCompact = "Compact"
    case gridMedium = "Medium"
    case gridLarge = "Large"
    case list = "List"

    var icon: String {
        switch self {
        case .gridCompact: return ThumbnailSize.compact.icon
        case .gridMedium: return ThumbnailSize.medium.icon
        case .gridLarge: return ThumbnailSize.large.icon
        case .list: return "list.bullet"
        }
    }

    var thumbnailSizeRaw: String {
        switch self {
        case .gridCompact: return ThumbnailSize.compact.rawValue
        case .gridMedium: return ThumbnailSize.medium.rawValue
        case .gridLarge: return ThumbnailSize.large.rawValue
        case .list: return ThumbnailSize.medium.rawValue
        }
    }
}

struct CategorySection: Identifiable {
    let id: String
    let name: String
    let items: [Item]
    let totalValue: Double
    /// Optional hex color for section header background (from category).
    var color: String?
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
    @Binding var viewMode: ItemViewMode
    @AppStorage("thumbnailSize") private var thumbnailSizeRaw: String = ThumbnailSize.medium.rawValue
    @State private var selectedItem: Item?
    @State private var showAddItem = false
    /// Per-category section search text (key = category section id); filters items within that section.
    @State private var sectionSearchTexts: [String: String] = [:]
    /// Per-category sort (key = category section id). When viewing a single category, that category id is used.
    @State private var sectionSortOrders: [String: ItemSortOrder] = [:]
    /// Collapse state lives in inventory so it persists when navigating to Categories tab and back.

    private var thumbnailSize: ThumbnailSize {
        ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium
    }

    /// One segmented control: Compact | Medium | Large | List (same bar as view options).
    private var displayChoiceBinding: Binding<ItemsDisplayChoice> {
        Binding(
            get: {
                if viewMode == .list { return .list }
                return ItemsDisplayChoice(rawValue: thumbnailSizeRaw) ?? .gridMedium
            },
            set: { choice in
                if choice == .list {
                    viewMode = .list
                } else {
                    viewMode = .grid
                    thumbnailSizeRaw = choice.thumbnailSizeRaw
                }
            }
        )
    }

    private var inventory: InventoryViewModel { session.inventory }
    private var categories: [Category] { session.categories.categories }
    private var collapsedSectionIds: Set<String> {
        get { inventory.categorySectionCollapsedIds }
        set { inventory.categorySectionCollapsedIds = newValue }
    }

    /// Display name for the current category (for title and dropdown).
    private var currentCategoryName: String {
        guard let id = inventory.selectedCategoryId, !id.isEmpty else { return "All Categories" }
        return categories.first(where: { $0.id == id })?.name ?? "All Categories"
    }

    /// Toolbar title: "N Items" when All, "N Items in [CATEGORY]" when a category is selected.
    private var toolbarTitle: String {
        let n = inventory.filteredItems.count
        guard let id = inventory.selectedCategoryId, !id.isEmpty else {
            return "\(n) Items"
        }
        return "\(n) Items in \(currentCategoryName)"
    }

    /// Total worth (price × quantity) of items in the current filtered view. Excludes items in a category named Wishlist.
    private var totalWorth: Double {
        inventory.filteredItems.reduce(0) { sum, item in
            let catName = categories.first(where: { $0.id == item.categoryId })?.name ?? ""
            if Category.isWishlist(catName) { return sum }
            let p = Double(item.price.trimmingCharacters(in: .whitespaces)) ?? 0
            return sum + p * Double(item.quantity)
        }
    }

    private var pinnedCategoryIds: Set<String> { session.categories.pinnedCategoryIds }

    /// When filter is "All", groups filtered items by category for subsectioned layout. Pinned categories always appear first.
    private var categorySections: [CategorySection] {
        let list = inventory.filteredItems
        let byCategory = Dictionary(grouping: list, by: { $0.categoryId })
        var sections: [CategorySection] = []
        let sortedCats = categories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for cat in sortedCats {
            guard let items = byCategory[cat.id], !items.isEmpty else { continue }
            let total = items.reduce(0.0) { sum, item in
                let p = Double(item.price.trimmingCharacters(in: .whitespaces)) ?? 0
                return sum + p * Double(item.quantity)
            }
            sections.append(CategorySection(id: cat.id, name: cat.name, items: items, totalValue: total, color: cat.color))
        }
        if let uncategorized = byCategory[""], !uncategorized.isEmpty {
            let total = uncategorized.reduce(0.0) { sum, item in
                let p = Double(item.price.trimmingCharacters(in: .whitespaces)) ?? 0
                return sum + p * Double(item.quantity)
            }
            sections.append(CategorySection(id: "", name: "Uncategorized", items: uncategorized, totalValue: total, color: nil))
        }
        let pinned = sections.filter { pinnedCategoryIds.contains($0.id) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let unpinned = sections.filter { !pinnedCategoryIds.contains($0.id) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return pinned + unpinned
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
                                VStack(spacing: 0) {
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
                                            sectionId: section.id,
                                            categoryColor: Color(hex: section.color),
                                            isPinned: pinnedCategoryIds.contains(section.id),
                                            isCollapsed: collapsedSectionIds.contains(section.id),
                                            onTogglePin: { session.categories.togglePinned(categoryId: section.id) },
                                            onTap: {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    var next = inventory.categorySectionCollapsedIds
                                                    if next.contains(section.id) {
                                                        next.remove(section.id)
                                                    } else {
                                                        next.insert(section.id)
                                                    }
                                                    inventory.categorySectionCollapsedIds = next
                                                }
                                            },
                                            onAddItem: {
                                                inventory.lastNewItemCategoryId = section.id
                                                showAddItem = true
                                            },
                                            onDropItem: { itemId in
                                                guard let item = inventory.items.first(where: { $0.id == itemId }),
                                                      item.categoryId != section.id else { return }
                                                var updated = item
                                                updated.categoryId = section.id
                                                Task { await inventory.updateItem(updated) }
                                            }
                                        )
                                        if !collapsedSectionIds.contains(section.id) {
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
                                                        .draggable(item.id)
                                                    }
                                                }
                                                .padding(.horizontal)
                                                .padding(.vertical, 12)
                                                .dropDestination(for: String.self) { itemIds, _ in
                                                    guard let itemId = itemIds.first,
                                                          let item = inventory.items.first(where: { $0.id == itemId }),
                                                          item.categoryId != section.id else { return false }
                                                    var updated = item
                                                    updated.categoryId = section.id
                                                    Task { await inventory.updateItem(updated) }
                                                    return true
                                                }
                                            }
                                        }
                                    }
                                }
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
                                        sectionId: singleCategoryId,
                                        categoryColor: categories.first(where: { $0.id == singleCategoryId }).flatMap { Color(hex: $0.color) },
                                        isPinned: pinnedCategoryIds.contains(singleCategoryId),
                                        isCollapsed: collapsedSectionIds.contains(singleCategoryId),
                                        onTogglePin: { session.categories.togglePinned(categoryId: singleCategoryId) },
                                        onTap: {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                var next = inventory.categorySectionCollapsedIds
                                                if next.contains(singleCategoryId) {
                                                    next.remove(singleCategoryId)
                                                } else {
                                                    next.insert(singleCategoryId)
                                                }
                                                inventory.categorySectionCollapsedIds = next
                                            }
                                        },
                                        onAddItem: {
                                            inventory.lastNewItemCategoryId = singleCategoryId
                                            showAddItem = true
                                        },
                                        onDropItem: { itemId in
                                            guard let item = inventory.items.first(where: { $0.id == itemId }),
                                                  item.categoryId != singleCategoryId else { return }
                                            var updated = item
                                            updated.categoryId = singleCategoryId
                                            Task { await inventory.updateItem(updated) }
                                        },
                                        showSearchField: false
                                    )
                                    if !collapsedSectionIds.contains(singleCategoryId) {
                                    LazyVGrid(columns: gridColumns, spacing: 16) {
                                        ForEach(singleCategorySorted) { item in
                                            ItemCardWithHoverPopover(
                                                item: item,
                                                categoryName: currentCategoryName,
                                                drive: session.drive,
                                                thumbnailSize: thumbnailSize,
                                                onTap: { selectedItem = item }
                                            )
                                            .draggable(item.id)
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 12)
                                    .dropDestination(for: String.self) { itemIds, _ in
                                        guard let itemId = itemIds.first,
                                              let item = inventory.items.first(where: { $0.id == itemId }),
                                              item.categoryId != singleCategoryId else { return false }
                                        var updated = item
                                        updated.categoryId = singleCategoryId
                                        Task { await inventory.updateItem(updated) }
                                        return true
                                    }
                                    }
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
                    Button { showAddItem = true } label: { Image(systemName: "plus") }
                        .help("Add item")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Text(toolbarTitle)
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ExportMenuView()
                }
                #else
                ToolbarItem(placement: .navigation) {
                    Button { showAddItem = true } label: { Image(systemName: "plus") }
                        .help("Add item")
                }
                #endif
                ToolbarItemGroup(placement: .primaryAction) {
                    if isShowingAllCategories ? !categorySections.isEmpty : (inventory.selectedCategoryId ?? "").isEmpty == false {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                let ids = isShowingAllCategories ? Set(categorySections.map(\.id)) : Set([inventory.selectedCategoryId ?? ""])
                                inventory.categorySectionCollapsedIds = ids
                            }
                        } label: { Image(systemName: "rectangle.compress.vertical") }
                        .help("Collapse all categories")
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                inventory.categorySectionCollapsedIds = []
                            }
                        } label: { Image(systemName: "rectangle.expand.vertical") }
                        .help("Expand all categories")
                    }
                    Picker("Display", selection: displayChoiceBinding) {
                        ForEach(ItemsDisplayChoice.allCases, id: \.rawValue) { choice in
                            Image(systemName: choice.icon).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Display: Compact, Medium, Large, or List")
                    HStack(spacing: 16) {
                        TextField("Search items", text: Binding(get: { inventory.searchText }, set: { inventory.searchText = $0 }))
                            .padding(.leading, 8)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 120, maxWidth: 200)
                            .help("Search items")
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
                ItemDetailView(item: item, onDismiss: { selectedItem = nil })
                    .environmentObject(session)
            }
            .sheet(isPresented: $showAddItem) {
                ItemFormView(mode: .add(initialWebLink: nil, initialCategoryId: nil))
                    .environmentObject(session)
                    .onDisappear { Task { await inventory.refresh() } }
            }
            .task { await inventory.refresh() }
            .onChange(of: categorySections.count) { _, newCount in
                if !inventory.hasAppliedInitialCategoryCollapse, newCount > 0 {
                    inventory.categorySectionCollapsedIds = Set(categorySections.filter { !Category.isWishlist($0.name) }.map(\.id))
                    inventory.hasAppliedInitialCategoryCollapse = true
                }
            }
            .onChange(of: inventory.selectedCategoryId) { _, newId in
                if !inventory.hasAppliedInitialCategoryCollapse, let id = newId, !id.isEmpty {
                    inventory.categorySectionCollapsedIds = [id]
                    inventory.hasAppliedInitialCategoryCollapse = true
                }
            }
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
    let locationName: String

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
            if !Category.isWishlist(categoryName) {
                LabeledRow(label: "Location", value: locationName)
            }
            LabeledRow(label: "Price", value: Item.priceInNIS(item.price))
            if !Category.isWishlist(categoryName) {
                LabeledRow(label: "Quantity", value: "\(item.quantity)")
                LabeledRow(label: "Purchase date", value: item.purchaseDate.isEmpty ? "—" : item.purchaseDate)
            }
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

/// Wraps an item card (hover popover disabled).
struct ItemCardWithHoverPopover: View {
    @EnvironmentObject var session: Session
    let item: Item
    let categoryName: String
    let drive: DriveService
    var thumbnailSize: ThumbnailSize = .medium
    var onTap: () -> Void

    private var thumbDimension: CGFloat { thumbnailSize.thumbnailDimension }

    var body: some View {
        ItemCard(item: item, drive: drive, photoId: item.photoIds.first, thumbnailSize: thumbnailSize)
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: thumbDimension, height: thumbDimension)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }
                    .contextMenu {
                        if !item.webLink.isEmpty, let url = URL(string: item.webLink) {
                            Button("Visit Product Page") {
                                #if os(iOS)
                                UIApplication.shared.open(url)
                                #elseif os(macOS)
                                NSWorkspace.shared.open(url)
                                #endif
                            }
                        }
                        Button("Search On YouTube") {
                            session.youtubeSearchQuery = item.name
                            session.requestedSidebarSelection = .youtube
                        }
                    }
            }
    }
}

// MARK: - Item card

struct ItemCard: View {
    let item: Item
    let drive: DriveService
    let photoId: String?
    var thumbnailSize: ThumbnailSize = .medium

    @State private var fillColor: Color?

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
                    .fill(fillColor ?? Color.gray.opacity(0.2))
                if let fileId = photoId {
                    DriveImageView(drive: drive, fileId: fileId, contentMode: .fit, onBackgroundColorDetected: { fillColor = $0 })
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
                Text(Item.priceInNIS(item.price))
                    .font(priceFont)
                    .foregroundStyle(.secondary)
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
    /// Fixed height so the header doesn't shrink when collapsed.
    static let fixedHeight: CGFloat = 44

    let name: String
    let itemCount: Int
    let totalValue: Double
    @Binding var sectionSearchText: String
    @Binding var sortOrder: ItemSortOrder
    var sectionId: String? = nil
    /// When set, used as the section header background color (from category color).
    var categoryColor: Color? = nil
    var isPinned: Bool = false
    var isCollapsed: Bool = false
    var onTogglePin: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil
    var onAddItem: (() -> Void)? = nil
    var onDropItem: ((String) -> Void)? = nil
    var showSearchField: Bool = true

    private var isWishlist: Bool { Category.isWishlist(name) }
    private var formattedValue: String {
        formatCurrency(totalValue)
    }

    @ViewBuilder
    private var headerBackground: some View {
        if let color = categoryColor {
            color.opacity(0.35)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private var sortOptions: [ItemSortOption] {
        if isWishlist {
            return ItemSortOption.allCases.filter { $0 != .purchaseDate }
        }
        return Array(ItemSortOption.allCases)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let onTap {
                Button {
                    onTap()
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if let onTogglePin {
                Button {
                    onTogglePin()
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.subheadline)
                        .foregroundStyle(isPinned ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
            Text("\(itemCount) item(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !isWishlist {
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Total: \(formattedValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !isCollapsed {
                HStack(spacing: 4) {
                    Text("Sort:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(sortOptions, id: \.rawValue) { option in
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
                            .foregroundStyle(.secondary)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: Self.fixedHeight, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .background(headerBackground)
        #if os(iOS)
        .overlay(alignment: .top) { Divider() }
        #endif
        .dropDestination(for: String.self) { itemIds, _ in
            guard let itemId = itemIds.first, let onDropItem else { return false }
            onDropItem(itemId)
            return true
        } isTargeted: { _ in }
    }
}

struct StatusBar: View {
    let totalWorth: Double
    let itemCount: Int

    private var formattedWorth: String {
        formatCurrency(totalWorth)
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
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
        }
    }
}
