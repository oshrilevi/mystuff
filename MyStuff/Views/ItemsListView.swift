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

    private var inventory: InventoryViewModel { session.inventory }
    private var categories: [Category] { session.categories.categories }

    private var currentCategoryName: String {
        guard let id = inventory.selectedCategoryId, !id.isEmpty else { return "All" }
        return categories.first(where: { $0.id == id })?.name ?? "All"
    }

    private var toolbarTitle: String {
        let n = inventory.filteredItems.count
        guard let id = inventory.selectedCategoryId, !id.isEmpty else {
            return "\(n) Items"
        }
        return "\(n) Items in \(currentCategoryName)"
    }

    private var totalWorth: Double {
        inventory.filteredItems.reduce(0) { sum, item in
            let p = Double(item.price.trimmingCharacters(in: .whitespaces)) ?? 0
            return sum + p * Double(item.quantity)
        }
    }

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if inventory.isLoading, inventory.items.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
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
                                        ForEach(sortedItemsForSection) { item in
                                            ItemListRow(
                                                item: item,
                                                categoryName: section.name,
                                                drive: session.drive
                                            )
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedItem = item }
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
                            } else {
                                let singleCategoryId = inventory.selectedCategoryId ?? ""
                                let singleCategorySorted = sortedItems(inventory.filteredItems, sectionId: singleCategoryId)
                                Section {
                                    ForEach(singleCategorySorted) { item in
                                        ItemListRow(
                                            item: item,
                                            categoryName: currentCategoryName,
                                            drive: session.drive
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedItem = item }
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
                                        onAddItem: {
                                            inventory.lastNewItemCategoryId = singleCategoryId
                                            showAddItem = true
                                        },
                                        showSearchField: false
                                    )
                                }
                            }
                        }
                        #if os(iOS)
                        .listStyle(.insetGrouped)
                        #else
                        .listStyle(.inset)
                        #endif
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
                    Picker("Display", selection: displayChoiceBinding) {
                        ForEach(ItemsDisplayChoice.allCases, id: \.rawValue) { choice in
                            Image(systemName: choice.icon).tag(choice)
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
}

private struct ItemListRow: View {
    let item: Item
    let categoryName: String
    let drive: DriveService

    private let thumbSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                if let fileId = item.photoIds.first {
                    DriveImageView(drive: drive, fileId: fileId, contentMode: .fill)
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
                    if !item.price.isEmpty {
                        Text(Item.priceInNIS(item.price))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
