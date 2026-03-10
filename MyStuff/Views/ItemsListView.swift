import SwiftUI

/// View mode for the Items tab: grid (gallery) or list.
enum ItemViewMode: String, CaseIterable {
    case grid = "Grid"
    case list = "List"

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

private func formatCurrency(_ value: Double) -> String {
    if value == 0 { return "₪ 0" }
    let rounded = (value * 100).rounded() / 100
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    return "₪ \(formatter.string(from: NSNumber(value: rounded)) ?? "0")"
}

struct ItemsListView: View {
    @EnvironmentObject var session: Session
    @Binding var viewMode: ItemViewMode
    @AppStorage("thumbnailSize") private var thumbnailSizeRaw: String = ThumbnailSize.medium.rawValue
    @State private var selectedItem: Item?
    @State private var showAddItem = false
    @State private var sectionSearchTexts: [String: String] = [:]
    @State private var sectionSortOrders: [String: ItemSortOrder] = [:]
    /// Collapse state lives in inventory so it persists when navigating to Categories tab and back.

    private var inventory: InventoryViewModel { session.inventory }
    private var collapsedSectionIds: Set<String> {
        get { inventory.categorySectionCollapsedIds }
        set { inventory.categorySectionCollapsedIds = newValue }
    }
    private var categories: [Category] { session.categories.categories }

    private var currentCategoryName: String {
        guard let id = inventory.selectedCategoryId, !id.isEmpty else { return "All Categories" }
        return categories.first(where: { $0.id == id })?.name ?? "All Categories"
    }

    private var toolbarTitle: String {
        let n = inventory.filteredItems.count
        guard let id = inventory.selectedCategoryId, !id.isEmpty else {
            return "\(n) Items"
        }
        return "\(n) Items in \(currentCategoryName)"
    }

    /// Excludes items in a category named Wishlist.
    private var totalWorth: Double {
        inventory.filteredItems.reduce(0) { sum, item in
            let catName = categories.first(where: { $0.id == item.categoryId })?.name ?? ""
            if Category.isWishlist(catName) { return sum }
            let p = Double(item.price.trimmingCharacters(in: .whitespaces)) ?? 0
            return sum + p * Double(item.quantity)
        }
    }

    private var pinnedCategoryIds: Set<String> { session.categories.pinnedCategoryIds }

    private var categorySections: [CategorySection] {
        let list = inventory.filteredItems
        let byCategory = Dictionary(grouping: list, by: { $0.categoryId })
        var sections: [CategorySection] = []
        let sortedCats = categories.sorted { ($0.order, $0.name.lowercased()) < ($1.order, $1.name.lowercased()) }
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
        let pinned = sections.filter { pinnedCategoryIds.contains($0.id) }
        let unpinned = sections.filter { !pinnedCategoryIds.contains($0.id) }
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

    /// Same single bar as GalleryView: Compact | Medium | Large | List.
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

    private var itemsListContent: some View {
        return List {
                            if let err = inventory.errorMessage {
                                Section {
                                    Text(err)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
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
                                        if !collapsedSectionIds.contains(section.id) {
                                            ForEach(Array(sortedItemsForSection.enumerated()), id: \.element.id) { index, item in
                                                ItemListRow(
                                                    item: item,
                                                    categoryName: section.name,
                                                    locationName: Category.isWishlist(section.name) ? "" : (session.locations.locations.first { $0.id == item.locationId }?.name ?? (item.locationId.isEmpty ? "" : "—")),
                                                    drive: session.drive,
                                                    currentStorePrice: session.storePriceCacheKey(webLink: item.webLink).flatMap { session.storePriceCache[$0] },
                                                    isPriceFetching: session.storePriceCacheKey(webLink: item.webLink).map { session.storePriceFetching.contains($0) } ?? false,
                                                    isPriceFailed: session.storePriceCacheKey(webLink: item.webLink).map { session.storePriceFailed.contains($0) } ?? false,
                                                    hasValidWebLink: session.storePriceCacheKey(webLink: item.webLink) != nil
                                                )
                                                .padding(.top, index == 0 ? 12 : 0)
                                                .padding(.bottom, index == sortedItemsForSection.count - 1 ? 12 : 0)
                                                .contentShape(Rectangle())
                                                .onTapGesture { selectedItem = item }
                                                .draggable(item.id)
                                            }
                                            .dropDestination(for: String.self) { itemIds, _ in
                                                guard let itemId = itemIds.first,
                                                      let item = inventory.items.first(where: { $0.id == itemId }),
                                                      item.categoryId != section.id else { return false }
                                                var updated = item
                                                updated.categoryId = section.id
                                                if Category.isWishlist(categories.first(where: { $0.id == item.categoryId })?.name ?? "") && !Category.isWishlist(section.name) {
                                                    updated.priceCurrency = ""
                                                }
                                                Task { await inventory.updateItem(updated) }
                                                return true
                                            }
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
                                                if Category.isWishlist(categories.first(where: { $0.id == item.categoryId })?.name ?? "") && !Category.isWishlist(section.name) {
                                                    updated.priceCurrency = ""
                                                }
                                                Task { await inventory.updateItem(updated) }
                                            }
                                        )
                                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    }
                                }
                                .listSectionSeparator(.hidden)
                            } else {
                                let singleCategoryId = inventory.selectedCategoryId ?? ""
                                let singleCategorySorted = sortedItems(inventory.filteredItems, sectionId: singleCategoryId)
                                Section {
                                    if !collapsedSectionIds.contains(singleCategoryId) {
                                        ForEach(Array(singleCategorySorted.enumerated()), id: \.element.id) { index, item in
                                            ItemListRow(
                                                item: item,
                                                categoryName: currentCategoryName,
                                                locationName: Category.isWishlist(currentCategoryName) ? "" : (session.locations.locations.first { $0.id == item.locationId }?.name ?? (item.locationId.isEmpty ? "" : "—")),
                                                drive: session.drive,
                                                currentStorePrice: session.storePriceCacheKey(webLink: item.webLink).flatMap { session.storePriceCache[$0] },
                                                isPriceFetching: session.storePriceCacheKey(webLink: item.webLink).map { session.storePriceFetching.contains($0) } ?? false,
                                                isPriceFailed: session.storePriceCacheKey(webLink: item.webLink).map { session.storePriceFailed.contains($0) } ?? false,
                                                hasValidWebLink: session.storePriceCacheKey(webLink: item.webLink) != nil
                                            )
                                            .padding(.top, index == 0 ? 12 : 0)
                                            .padding(.bottom, index == singleCategorySorted.count - 1 ? 12 : 0)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedItem = item }
                                            .draggable(item.id)
                                        }
                                        .dropDestination(for: String.self) { itemIds, _ in
                                            guard let itemId = itemIds.first,
                                                  let item = inventory.items.first(where: { $0.id == itemId }),
                                                  item.categoryId != singleCategoryId else { return false }
                                            var updated = item
                                            updated.categoryId = singleCategoryId
                                            if Category.isWishlist(categories.first(where: { $0.id == item.categoryId })?.name ?? "") && !Category.isWishlist(currentCategoryName) {
                                                updated.priceCurrency = ""
                                            }
                                            Task { await inventory.updateItem(updated) }
                                            return true
                                        }
                                    }
                                } header: {
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
                                            if Category.isWishlist(categories.first(where: { $0.id == item.categoryId })?.name ?? "") && !Category.isWishlist(currentCategoryName) {
                                                updated.priceCurrency = ""
                                            }
                                            Task { await inventory.updateItem(updated) }
                                        },
                                        showSearchField: false
                                    )
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                }
                                .listSectionSeparator(.hidden)
                            }
        }
        .modifier(ItemsListStyleModifier())
        .modifier(ItemsListSectionSpacingModifier())
        .refreshable { await inventory.refresh() }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if inventory.isLoading, inventory.items.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        itemsListContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                StatusBar(totalWorth: totalWorth, itemCount: inventory.filteredItems.count)
            }
            .task {
                await session.prefetchWishlistPricesIfNeeded()
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
                        ItemsListSearchField(text: Binding(get: { inventory.searchText }, set: { inventory.searchText = $0 }))
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
}

private struct ItemsListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.listStyle(.insetGrouped)
        #else
        content.listStyle(.inset)
        #endif
    }
}

#if os(iOS)
private struct ItemsListSectionSpacingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listSectionSpacing(0)
            .listRowSpacing(0)
    }
}
#else
private struct ItemsListSectionSpacingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
#endif

private struct ItemsListSearchField: View {
    @Binding var text: String
    var body: some View {
        TextField("Search items", text: $text)
            .padding(.leading, 8)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 120, maxWidth: 200)
            .help("Search items")
        #if os(iOS)
            .focusEffectDisabled()
        #endif
    }
}

private struct ItemListRow: View {
    let item: Item
    let categoryName: String
    let locationName: String
    let drive: DriveService
    /// When set (wishlist item with cached store price), shown next to the entered price.
    var currentStorePrice: String? = nil
    /// True while this item's URL is being fetched for current price.
    var isPriceFetching: Bool = false
    /// True when fetch was attempted and failed (show red dash only then).
    var isPriceFailed: Bool = false
    /// True when item has a valid web link (so we show fetching/price/dash); when false for wishlist, show nothing.
    var hasValidWebLink: Bool = true

    @State private var fillColor: Color?

    private let thumbSize: CGFloat = 44
    private var isWishlist: Bool { Category.isWishlist(categoryName) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(fillColor ?? Color.gray.opacity(0.2))
                if let fileId = item.photoIds.first {
                    DriveImageView(drive: drive, fileId: fileId, contentMode: .fit, onBackgroundColorDetected: { fillColor = $0 })
                        .frame(width: thumbSize, height: thumbSize)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: thumbSize, height: thumbSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Text(Item.formattedPrice(price: item.price, priceCurrency: item.priceCurrency, isWishlist: isWishlist))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isWishlist, hasValidWebLink, isPriceFetching || currentStorePrice != nil || isPriceFailed {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if isPriceFetching {
                            Text("Fetching…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let current = currentStorePrice, !current.isEmpty {
                            let trend = Item.priceTrend(entered: item.price, current: current)
                            HStack(spacing: 2) {
                                Text("Current: \(Item.formattedPrice(price: current, priceCurrency: item.priceCurrency, isWishlist: true))")
                                    .font(.caption)
                                    .foregroundStyle(trend == .higher ? .red : (trend == .lower ? .green : .secondary))
                                if trend != .same {
                                    Image(systemName: trend == .higher ? "arrow.up" : "arrow.down")
                                        .font(.caption2)
                                        .foregroundStyle(trend == .higher ? .red : .green)
                                }
                            }
                        } else if isPriceFailed {
                            Text("—")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !locationName.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(locationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if item.quantity > 1 {
                        Text("× \(item.quantity)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
