import SwiftUI

struct ComboItemSelectionView: View {
    @EnvironmentObject var session: Session

    let combo: Combo
    let initiallySelectedIds: Set<String>
    let onDone: ([Item]) -> Void
    let onCancel: () -> Void

    @State private var selectedIds: Set<String> = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false

    private var inventory: InventoryViewModel { session.inventory }
    private var categories: [Category] { session.categories.categories }

    private var allItems: [Item] {
        // Exclude items that belong to the Wishlist category from combo selection.
        let wishlistCategoryIds = Set(categories.filter { Category.isWishlist($0.name) }.map(\.id))
        if wishlistCategoryIds.isEmpty {
            return inventory.items
        }
        return inventory.items.filter { !wishlistCategoryIds.contains($0.categoryId) }
    }

    private var filteredItems: [Item] {
        var result = allItems

        // Apply text search.
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
            VStack(spacing: 0) {
                // Text filter row (always visible at the top of the dialog)
                HStack(spacing: 12) {
                    searchField
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

                List {
                    if isLoading && allItems.isEmpty {
                        Section {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Loading items…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                        }
                    } else if allItems.isEmpty {
                        Section {
                            Text("No items available in inventory to add to this combo.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        }
                    } else if filteredItems.isEmpty {
                        Section {
                            Text("No items match the current search.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        }
                    } else {
                        ForEach(filteredItems) { item in
                            HStack(spacing: 12) {
                                ItemThumbnailView(
                                    drive: session.drive,
                                    photoId: item.photoIds.first,
                                    size: 44,
                                    cornerRadius: 8,
                                    placeholderFont: .title2
                                )

                                VStack(alignment: .leading, spacing: 4) {
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

                                Spacer()

                                Image(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedIds.contains(item.id) ? .accentColor : .secondary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(for: item.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add items to \"\(combo.name)\"")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedIds.count) item(s)") {
                        let toAdd = allItems.filter { selectedIds.contains($0.id) }
                        onDone(toAdd)
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
            .onAppear {
                selectedIds = initiallySelectedIds
                Task {
                    isLoading = true
                    await inventory.refresh()
                    isLoading = false
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
        #endif
    }

    private var searchField: some View {
        ZStack(alignment: .trailing) {
            TextField("Search by name, description, or tag", text: $searchText)
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

