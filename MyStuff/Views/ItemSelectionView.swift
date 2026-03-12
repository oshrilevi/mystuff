import SwiftUI

struct ItemSelectionView: View {
    @EnvironmentObject var session: Session

    let list: UserList
    let initiallySelectedIds: Set<String>
    let onDone: ([Item]) -> Void
    let onCancel: () -> Void

    @State private var selectedIds: Set<String> = []
    @State private var searchText: String = ""

    private var inventory: InventoryViewModel { session.inventory }
    private var categories: [Category] { session.categories.categories }

    private var allItems: [Item] {
        inventory.items
    }

    private var filteredItems: [Item] {
        var result = allItems
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
                ForEach(filteredItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedIds.contains(item.id) ? .accentColor : .secondary)
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
            .navigationTitle("Add items to \"\(list.name)\"")
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
                ToolbarItem(placement: .principal) {
                    searchField
                }
            }
            .onAppear {
                selectedIds = initiallySelectedIds
            }
        }
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

