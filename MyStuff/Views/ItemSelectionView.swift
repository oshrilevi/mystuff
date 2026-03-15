import SwiftUI

struct ItemSelectionView: View {
    @EnvironmentObject var session: Session
    /// The list we're adding items to (used for title only).
    let list: UserList
    /// Snapshot of all available items at the time the picker is presented.
    let allItems: [Item]
    /// Snapshot of categories for display.
    let categories: [Category]
    /// Items that are already in the list when opening the picker.
    let initiallySelectedIds: Set<String>
    let onDone: ([Item]) -> Void
    let onCancel: () -> Void

    @State private var selectedIds: Set<String> = []
    @State private var searchText: String = ""

    /// Items available to add to the list; excludes Wishlist category so you only add owned items.
    private var selectableItems: [Item] {
        let wishlistCategoryIds = Set(categories.filter { Category.isWishlist($0.name) }.map(\.id))
        if wishlistCategoryIds.isEmpty { return allItems }
        return allItems.filter { !wishlistCategoryIds.contains($0.categoryId) }
    }

    private var filteredItems: [Item] {
        var result = selectableItems
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q)
                || $0.description.lowercased().contains(q)
                || $0.tags.contains { $0.lowercased().contains(q) }
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    searchField
                }
                if filteredItems.isEmpty {
                    Section {
                        Text("No items available yet. Add items from the Inventory section first, or adjust your search.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                } else {
                    ForEach(filteredItems) { item in
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedIds.contains(item.id) ? .accentColor : .secondary)
                                .frame(width: 24, height: 40, alignment: .center)
                            ItemThumbnailView(
                                drive: session.drive,
                                photoId: item.photoIds.first,
                                size: 40,
                                cornerRadius: 8,
                                placeholderFont: .title3
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.body)
                                HStack(spacing: 6) {
                                    if let catName = categories.first(where: { $0.id == item.categoryId })?.name {
                                        Text(catName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !item.tags.isEmpty {
                                        Text(item.tags.joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSelection(for: item.id)
                        }
                    }
                }
            }
            .navigationTitle("Add items to \"\(list.name)\"")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedIds.count) item(s)") {
                        let toAdd = selectableItems.filter { selectedIds.contains($0.id) }
                        onDone(toAdd)
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
            .onAppear {
                selectedIds = initiallySelectedIds
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
        #endif
    }

    private var searchField: some View {
        ZStack(alignment: .trailing) {
            TextField("Search items", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160, maxWidth: 260)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleSelection(for id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }
}

