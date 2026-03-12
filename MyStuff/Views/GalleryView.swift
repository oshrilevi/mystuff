import SwiftUI
import AppKit

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
    /// SF Symbol name for section icon (from category).
    var iconSymbol: String?
    /// Drive file ID for custom section icon (from category).
    var iconFileId: String?
}

/// Groups one or more category sections under a single parent category (for hierarchy in the Gallery).
struct CategoryGroup: Identifiable {
    let id: String          // parent category id, or section id for standalone / Uncategorized
    let name: String        // parent category name (or section name for standalone)
    var sections: [CategorySection]
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
    @State private var selectedAttachment: ItemAttachment?
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

    /// When filter is "All", groups filtered items by category for subsectioned layout.
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
            sections.append(CategorySection(id: cat.id, name: cat.name, items: items, totalValue: total, iconSymbol: cat.iconSymbol, iconFileId: cat.iconFileId))
        }
        if let uncategorized = byCategory[""], !uncategorized.isEmpty {
            let total = uncategorized.reduce(0.0) { sum, item in
                let p = Double(item.price.trimmingCharacters(in: .whitespaces)) ?? 0
                return sum + p * Double(item.quantity)
            }
            sections.append(CategorySection(id: "", name: "Uncategorized", items: uncategorized, totalValue: total, iconSymbol: nil, iconFileId: nil))
        }
        return sections
    }

    /// Parent groups with their child category sections, used to visually nest subcategories under parents.
    private var categoryGroups: [CategoryGroup] {
        var groups: [String: CategoryGroup] = [:]

        for section in categorySections {
            // Uncategorized has no Category model; treat as its own group.
            guard !section.id.isEmpty,
                  let cat = categories.first(where: { $0.id == section.id }) else {
                let key = section.id
                var group = groups[key] ?? CategoryGroup(id: key, name: section.name, sections: [])
                group.sections.append(section)
                groups[key] = group
                continue
            }

            let parentId = (cat.parentId?.isEmpty == false) ? cat.parentId! : cat.id
            let parentCat = categories.first(where: { $0.id == parentId }) ?? cat
            let key = parentId
            var group = groups[key] ?? CategoryGroup(id: key, name: parentCat.name, sections: [])
            group.sections.append(section)
            groups[key] = group
        }

        // Sort sections within each group by category order/name.
        for (key, group) in groups {
            var sorted = group.sections
            sorted.sort { a, b in
                let aOrder = categories.first(where: { $0.id == a.id })?.order ?? Int.max
                let bOrder = categories.first(where: { $0.id == b.id })?.order ?? Int.max
                return (aOrder, a.name.lowercased()) < (bOrder, b.name.lowercased())
            }
            groups[key]?.sections = sorted
        }

        // Sort parent groups by parent category order/name.
        var result = Array(groups.values)
        result.sort { lhs, rhs in
            let lhsOrder = categories.first(where: { $0.id == lhs.id })?.order ?? Int.max
            let rhsOrder = categories.first(where: { $0.id == rhs.id })?.order ?? Int.max
            return (lhsOrder, lhs.name.lowercased()) < (rhsOrder, rhs.name.lowercased())
        }
        return result
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
                                    ForEach(categoryGroups) { group in
                                        let parentCollapsed = collapsedSectionIds.contains(group.id)
                                        let isLastCategory = group.id == categoryGroups.last?.id
                                        // Show a parent label when group actually has subcategories (sections whose id differs from the parent group id).
                                        if group.sections.contains(where: { $0.id != group.id }) {
                                            let groupItemCount = group.sections.reduce(0) { $0 + $1.items.count }
                                            let groupTotalValue: Double = group.sections.reduce(0) { sum, sec in
                                                Category.isWishlist(sec.name) ? sum : sum + sec.totalValue
                                            }
                                            HStack(alignment: .center, spacing: 8) {
                                                CategoryIconView(
                                                    iconSymbol: categories.first(where: { $0.id == group.id })?.iconSymbol,
                                                    iconFileId: categories.first(where: { $0.id == group.id })?.iconFileId,
                                                    drive: session.drive,
                                                    size: 22
                                                )
                                                Text(group.name)
                                                    .font(.headline)
                                                if parentCollapsed {
                                                    HStack(spacing: 4) {
                                                        Text("\(groupItemCount) item(s)")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                        if group.sections.contains(where: { !Category.isWishlist($0.name) }) {
                                                            Text("·")
                                                                .font(.caption)
                                                                .foregroundStyle(.tertiary)
                                                            Text("Total: \(formatCurrency(groupTotalValue))")
                                                                .font(.caption)
                                                                .foregroundStyle(.secondary)
                                                        }
                                                    }
                                                    .padding(.leading, 10)
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, minHeight: CategorySectionHeader.fixedHeight, alignment: .leading)
                                            .background(GalleryView.sectionBackground(isTopLevel: true, isSubcategory: false))
                                            .overlay(alignment: .bottom) {
                                                if parentCollapsed && !isLastCategory { Divider() }
                                            }
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    var next = inventory.categorySectionCollapsedIds
                                                    let currentlyCollapsed = next.contains(group.id)
                                                    if currentlyCollapsed {
                                                        // Expand: only expand the parent group; keep child sections' states as-is.
                                                        next.remove(group.id)
                                                    } else {
                                                        // Collapse: hide the entire group but do not change child sections' states.
                                                        next.insert(group.id)
                                                    }
                                                    inventory.categorySectionCollapsedIds = next
                                                }
                                            }
                                        }
                                        // When a parent is collapsed, hide all child sections entirely.
                                        ForEach(group.sections.filter { !parentCollapsed || $0.id == group.id }) { section in
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
                                            let isParentSection = section.id == group.id
                                            let isSubcategory = !isParentSection
                                            let subcategories = group.sections.filter { $0.id != group.id }
                                            let isLastSubcategoryInGroup = !isSubcategory || subcategories.last?.id == section.id
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
                                                iconSymbol: section.iconSymbol,
                                                iconFileId: section.iconFileId,
                                                drive: session.drive,
                                                isCollapsed: isParentSection ? parentCollapsed : collapsedSectionIds.contains(section.id),
                                                isSubcategory: isSubcategory,
                                                isLastSubcategoryInGroup: isLastSubcategoryInGroup,
                                                isLastCategoryInGallery: isLastCategory,
                                                onTap: {
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        var next = inventory.categorySectionCollapsedIds
                                                        if isParentSection {
                                                            // Toggle only the parent group's collapsed state; do not touch child sections.
                                                            let currentlyCollapsed = next.contains(group.id)
                                                            if currentlyCollapsed {
                                                                next.remove(group.id)
                                                            } else {
                                                                next.insert(group.id)
                                                            }
                                                        } else {
                                                            if next.contains(section.id) {
                                                                next.remove(section.id)
                                                            } else {
                                                                next.insert(section.id)
                                                            }
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
                                                                onTap: { selectedItem = item },
                                                                onOpenAttachment: { att in
                                                                    Task {
                                                                        await AttachmentOpener.open(att, itemName: item.name, drive: session.drive)
                                                                    }
                                                                }
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
                                                        if Category.isWishlist(categories.first(where: { $0.id == item.categoryId })?.name ?? "") && !Category.isWishlist(section.name) {
                                                            updated.priceCurrency = ""
                                                        }
                                                        Task { await inventory.updateItem(updated) }
                                                        return true
                                                    }
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
                                        iconSymbol: categories.first(where: { $0.id == singleCategoryId })?.iconSymbol,
                                        iconFileId: categories.first(where: { $0.id == singleCategoryId })?.iconFileId,
                                        drive: session.drive,
                                        isCollapsed: collapsedSectionIds.contains(singleCategoryId),
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
                                    if !collapsedSectionIds.contains(singleCategoryId) {
                                    LazyVGrid(columns: gridColumns, spacing: 16) {
                                        ForEach(singleCategorySorted) { item in
                                            ItemCardWithHoverPopover(
                                                item: item,
                                                categoryName: currentCategoryName,
                                                drive: session.drive,
                                                thumbnailSize: thumbnailSize,
                                                onTap: { selectedItem = item },
                                                onOpenAttachment: { att in
                                                    Task {
                                                        await AttachmentOpener.open(att, itemName: item.name, drive: session.drive)
                                                    }
                                                }
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
                                        if Category.isWishlist(categories.first(where: { $0.id == item.categoryId })?.name ?? "") && !Category.isWishlist(currentCategoryName) {
                                            updated.priceCurrency = ""
                                        }
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
            .task {
                await session.prefetchWishlistPricesIfNeeded()
            }
            .navigationTitle(toolbarTitle)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { showAddItem = true } label: { Image(systemName: "plus") }
                        .help("Add item")
                }
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
                        ZStack(alignment: .trailing) {
                            TextField("Search items", text: Binding(get: { inventory.searchText }, set: { inventory.searchText = $0 }))
                                .padding(.leading, 8)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 120, maxWidth: 200)
                                .help("Search items")
                            if !inventory.searchText.isEmpty {
                                Button {
                                    inventory.searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 8)
                            }
                        }
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
            .task {
                await inventory.refresh()
                if session.lists.lists.isEmpty {
                    await session.lists.load()
                }
            }
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
            .onChange(of: inventory.searchText) { _, newSearch in
                guard !newSearch.isEmpty else { return }
                let idsWithMatches = Set(inventory.filteredItems.map { $0.categoryId })
                if !idsWithMatches.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        inventory.categorySectionCollapsedIds.subtract(idsWithMatches)
                    }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize.gridMinimum), spacing: 16)]
    }

    /// Background color for category/section headers: top-level vs subcategory (same hue, top-level slightly darker).
    static func sectionBackground(isTopLevel: Bool, isSubcategory: Bool) -> Color {
        if isTopLevel {
            return Color.primary.opacity(0.11)
        }
        return Color.primary.opacity(0.08)
    }
}

// MARK: - Hover popover (macOS)

/// Compact popover content showing all item fields after 1s hover.
struct ItemHoverPopoverContent: View {
    @EnvironmentObject var session: Session
    let item: Item
    let categoryName: String
    let locationName: String

    private var currentStorePrice: String? {
        session.storePriceCacheKey(webLink: item.webLink).flatMap { session.storePriceCache[$0] }
    }

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
            LabeledRow(label: "Price", value: Item.formattedPrice(price: item.price, priceCurrency: item.priceCurrency, isWishlist: Category.isWishlist(categoryName)))
            if Category.isWishlist(categoryName) {
                if let current = currentStorePrice, !current.isEmpty {
                    let trend = Item.priceTrend(entered: item.price, current: current)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Current")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 80, alignment: .leading)
                        HStack(spacing: 4) {
                            Text(Item.formattedPrice(price: current, priceCurrency: item.priceCurrency, isWishlist: true))
                                .font(.caption)
                                .foregroundStyle(trend == .higher ? .red : (trend == .lower ? .green : .secondary))
                            if trend != .same {
                                Image(systemName: trend == .higher ? "arrow.up" : "arrow.down")
                                    .font(.caption2)
                                    .foregroundStyle(trend == .higher ? .red : .green)
                            }
                        }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Current")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 80, alignment: .leading)
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            if !Category.isWishlist(categoryName) {
                LabeledRow(label: "Quantity", value: "\(item.quantity)")
                LabeledRow(label: "Purchase date", value: item.purchaseDate.isEmpty ? "—" : item.purchaseDate)
            }
            if !item.tags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tags")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TagChipsView(tags: item.tags)
                }
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
    var onOpenAttachment: (ItemAttachment) -> Void

    @State private var isEditingFromMenu = false
    @State private var showDeleteConfirmationFromMenu = false

    private var thumbDimension: CGFloat { thumbnailSize.thumbnailDimension }

    var body: some View {
        ItemCard(
            item: item,
            drive: drive,
            photoId: item.photoIds.first,
            categoryName: categoryName,
            thumbnailSize: thumbnailSize,
            currentStorePrice: session.storePriceCacheKey(webLink: item.webLink).flatMap { session.storePriceCache[$0] },
            isPriceFetching: session.storePriceCacheKey(webLink: item.webLink).map { session.storePriceFetching.contains($0) } ?? false,
            isPriceFailed: session.storePriceCacheKey(webLink: item.webLink).map { session.storePriceFailed.contains($0) } ?? false,
            hasValidWebLink: session.storePriceCacheKey(webLink: item.webLink) != nil
        )
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: thumbDimension, height: thumbDimension)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }
                    .contextMenu {
                        ItemContextMenuContent(
                            item: item,
                            categoryName: categoryName,
                            session: session,
                            onOpenAttachment: onOpenAttachment,
                            onView: onTap,
                            onEdit: { isEditingFromMenu = true },
                            onDelete: { showDeleteConfirmationFromMenu = true }
                        )
                    }
            }
        .sheet(isPresented: $isEditingFromMenu) {
            ItemFormView(
                mode: .edit(item),
                onSaveSuccess: { _ in
                    isEditingFromMenu = false
                    Task { await session.inventory.refresh() }
                },
                onCancel: {
                    isEditingFromMenu = false
                }
            )
            .environmentObject(session)
        }
        .confirmationDialog("Delete item?", isPresented: $showDeleteConfirmationFromMenu, titleVisibility: .visible) {
            Button("Delete \"\(item.name.count > 75 ? String(item.name.prefix(75)) + "…" : item.name)\"", role: .destructive) {
                Task {
                    await session.inventory.deleteItems(ids: [item.id])
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. The item will be removed from your inventory.")
        }
    }
}

struct ItemContextMenuContent: View {
    let item: Item
    let categoryName: String
    @ObservedObject var session: Session
    var onOpenAttachment: (ItemAttachment) -> Void
    var onView: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var attachments: [ItemAttachment] {
        session.attachments.attachments(for: item.id)
    }

    private var trimmedName: String {
        item.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var productURL: URL? {
        let s = item.webLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let u = URL(string: s) else { return nil }
        return u
    }

    /// Builds an Amazon search query from the item's tags, falling back to the item name.
    /// Tags that contain “amazon” or “amazon.com” are removed to avoid vendor noise.
    private var amazonSearchQuery: String? {
        let cleanedTags = item.tags.filter { tag in
            let lower = tag.lowercased()
            return !lower.contains("amazon.com") && !lower.contains("amazon")
        }
        let terms: [String]
        if !cleanedTags.isEmpty {
            terms = cleanedTags
        } else {
            let name = trimmedName
            guard !name.isEmpty else { return nil }
            terms = [name]
        }
        let query = terms.joined(separator: " ")
        return query.isEmpty ? nil : query
    }

    private var hasSearchActions: Bool {
        productURL != nil || !trimmedName.isEmpty || amazonSearchQuery != nil
    }

    var body: some View {
        let isWishlist = Category.isWishlist(categoryName)
        let locationName: String = {
            if isWishlist { return "" }
            return session.locations.locations.first { $0.id == item.locationId }?.name ?? (item.locationId.isEmpty ? "" : "—")
        }()
        let priceText = Item.formattedPrice(price: item.price, priceCurrency: item.priceCurrency, isWishlist: isWishlist)
        let categoryLine: String = {
            var parts: [String] = [categoryName]
            if !locationName.isEmpty {
                parts.append(locationName)
            }
            parts.append(priceText)
            return parts.joined(separator: " - ")
        }()

        return VStack(alignment: .leading, spacing: 4) {
            // Header: item info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(categoryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)
            .multilineTextAlignment(.leading)

            Divider()

            // Search section
            if hasSearchActions {
                Text("Search")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let url = productURL {
                    Button {
                        #if os(iOS)
                        UIApplication.shared.open(url)
                        #elseif os(macOS)
                        NSWorkspace.shared.open(url)
                        #endif
                    } label: {
                        Label("Open product page", systemImage: "safari")
                    }
                }

                if !trimmedName.isEmpty {
                    Button {
                        session.youtubeSearchQuery = trimmedName
                        session.requestedSidebarSelection = .youtube
                    } label: {
                        Label("Search on YouTube", systemImage: "play.rectangle")
                    }
                }

                if let query = amazonSearchQuery {
                    Button {
                        session.amazonSearchQuery = query
                        if let amazonStore = session.stores.stores.first(where: { $0.startURL.lowercased().contains("amazon.com") }) {
                            session.requestedSidebarSelection = .store(amazonStore)
                        }
                    } label: {
                        Label("Search for similar items on Amazon", systemImage: "cart")
                    }
                }
            }

            // Documents section
            if !attachments.isEmpty {
                Divider()

                Text("Documents")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(attachments) { att in
                    Button {
                        onOpenAttachment(att)
                    } label: {
                        Label(att.kind.displayTitle, systemImage: "doc.fill")
                    }
                }
            }

            // Lists section
            Divider()
            Menu {
                if session.lists.lists.isEmpty {
                    Button("No lists yet") {}
                        .disabled(true)
                } else {
                    ForEach(session.lists.lists) { list in
                        let isInList = session.lists.listItems.contains { entry in
                            entry.listId == list.id && entry.itemId == item.id
                        }
                        Button {
                            Task {
                                if isInList {
                                    await session.lists.removeItems([item], from: list)
                                } else {
                                    await session.lists.addItems([item], to: list)
                                }
                            }
                        } label: {
                            Label(
                                list.name,
                                systemImage: isInList ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                }
            } label: {
                Label("Add to list", systemImage: "text.badge.plus")
            }

            Divider()
            Text("Item Actions")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button {
                onView()
            } label: {
                Label("View", systemImage: "eye")
            }
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }
}

// MARK: - Item card

struct ItemCard: View {
    let item: Item
    let drive: DriveService
    let photoId: String?
    let categoryName: String
    var thumbnailSize: ThumbnailSize = .medium
    /// When set (wishlist item with cached store price), shown next to the entered price.
    var currentStorePrice: String? = nil
    /// True while this item's URL is being fetched for current price.
    var isPriceFetching: Bool = false
    /// True when fetch was attempted and failed (show red dash only then).
    var isPriceFailed: Bool = false
    /// True when item has a valid web link (so we show fetching/price/dash).
    var hasValidWebLink: Bool = true

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
            ItemThumbnailView(
                drive: drive,
                photoId: photoId,
                size: thumbDimension,
                cornerRadius: thumbnailSize == .compact ? 8 : 12,
                placeholderFont: iconFont
            )
            Text(item.name)
                .font(titleFont)
                .fontWeight(.medium)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(Item.formattedPrice(price: item.price, priceCurrency: item.priceCurrency, isWishlist: Category.isWishlist(categoryName)))
                    .font(priceFont)
                    .foregroundStyle(.secondary)
                if Category.isWishlist(categoryName), hasValidWebLink, isPriceFetching || currentStorePrice != nil || isPriceFailed {
                    Text("·")
                        .font(priceFont)
                        .foregroundStyle(.tertiary)
                    if isPriceFetching {
                        Text("Fetching…")
                            .font(priceFont)
                            .foregroundStyle(.secondary)
                    } else if let current = currentStorePrice, !current.isEmpty {
                        let trend = Item.priceTrend(entered: item.price, current: current)
                        HStack(spacing: 2) {
                            Text("Current: \(Item.formattedPrice(price: current, priceCurrency: item.priceCurrency, isWishlist: true))")
                                .font(priceFont)
                                .foregroundStyle(trend == .higher ? .red : (trend == .lower ? .green : .secondary))
                            if trend != .same {
                                Image(systemName: trend == .higher ? "arrow.up" : "arrow.down")
                                    .font(.caption2)
                                    .foregroundStyle(trend == .higher ? .red : .green)
                            }
                        }
                    } else if isPriceFailed {
                        Text("—")
                            .font(priceFont)
                            .foregroundStyle(.red)
                    }
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

/// Shared thumbnail view used by both the gallery cards and list rows so that
/// thumbnails have consistent background fill and rounded corners.
struct ItemThumbnailView: View {
    let drive: DriveService
    let photoId: String?
    let size: CGFloat
    let cornerRadius: CGFloat
    let placeholderFont: Font

    @State private var fillColor: Color?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(fillColor ?? Color.gray.opacity(0.2))
            if let fileId = photoId {
                DriveImageView(
                    drive: drive,
                    fileId: fileId,
                    contentMode: .fit,
                    onBackgroundColorDetected: { fillColor = $0 }
                )
                .frame(width: size, height: size)
                .clipped()
                .cornerRadius(cornerRadius)
            } else {
                Image(systemName: "photo")
                    .font(placeholderFont)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Displays a category icon: SF Symbol or custom image loaded from Drive (Documents folder).
struct CategoryIconView: View {
    var iconSymbol: String?
    var iconFileId: String?
    var drive: DriveService?
    var size: CGFloat = 24

    @State private var imageData: Data?

    var body: some View {
        Group {
            if let fileId = iconFileId, let drive = drive {
                if let data = imageData {
                    imageFromData(data)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: size * 0.7))
                        .foregroundStyle(.secondary)
                }
            } else if let symbol = iconSymbol, !symbol.isEmpty {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.85))
                    .foregroundStyle(.secondary)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .task(id: iconFileId) {
            guard let fileId = iconFileId, let drive = drive else { return }
            guard imageData == nil else { return }
            imageData = try? await drive.fetchFileData(fileId: fileId)
        }
    }

    @ViewBuilder
    private func imageFromData(_ data: Data) -> some View {
        #if os(iOS)
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "photo")
                .font(.system(size: size * 0.7))
                .foregroundStyle(.secondary)
        }
        #elseif os(macOS)
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "photo")
                .font(.system(size: size * 0.7))
                .foregroundStyle(.secondary)
        }
        #else
        Image(systemName: "photo")
        #endif
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
    var iconSymbol: String? = nil
    var iconFileId: String? = nil
    var drive: DriveService? = nil
    var isCollapsed: Bool = false
    /// True when this section is a subcategory under a parent (different background from top-level).
    var isSubcategory: Bool = false
    /// When isSubcategory, false = show a bottom border; true = no border (last subcategory in group).
    var isLastSubcategoryInGroup: Bool = true
    /// When true, collapsed state does not show a bottom border (last category in the list).
    var isLastCategoryInGallery: Bool = true
    var onTap: (() -> Void)? = nil
    var onAddItem: (() -> Void)? = nil
    var onDropItem: ((String) -> Void)? = nil
    var showSearchField: Bool = true

    private var isWishlist: Bool { Category.isWishlist(name) }
    private var formattedValue: String {
        formatCurrency(totalValue)
    }

    private var headerBackground: some View {
        Rectangle().fill(GalleryView.sectionBackground(isTopLevel: !isSubcategory, isSubcategory: isSubcategory))
    }

    private var sortOptions: [ItemSortOption] {
        if isWishlist {
            return ItemSortOption.allCases.filter { $0 != .purchaseDate }
        }
        return Array(ItemSortOption.allCases)
    }

    /// When collapsed, keep count and total tight next to the title (like parent group header).
    private var titleAndSummary: some View {
        HStack(alignment: .center, spacing: 8) {
            CategoryIconView(iconSymbol: iconSymbol, iconFileId: iconFileId, drive: drive, size: 22)
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
            HStack(spacing: 4) {
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
            }
            .padding(.leading, 10)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            titleAndSummary
            if !isCollapsed {
                Spacer(minLength: 8)
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
                    ZStack(alignment: .trailing) {
                        TextField("Filter in \(name)", text: $sectionSearchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 100, maxWidth: 180)
                        #if os(iOS)
                        .focusEffectDisabled()
                        #endif
                        if !sectionSearchText.isEmpty {
                            Button {
                                sectionSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                        }
                    }
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
        .overlay(alignment: .bottom) {
            if (isSubcategory && !isLastSubcategoryInGroup) || (isCollapsed && !isLastCategoryInGallery) {
                Divider()
            }
        }
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
