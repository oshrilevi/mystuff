import SwiftUI

struct ListDetailView: View {
    @EnvironmentObject var session: Session

    let list: UserList

    @State private var selectedItem: Item?
    @State private var showItemPicker = false
    @State private var showComboPicker = false

    private var listsVM: ListsViewModel { session.lists }
    private var inventory: InventoryViewModel { session.inventory }

    private var itemsInList: [Item] {
        listsVM.items(for: list, from: inventory.items)
    }

    private var shareText: String {
        var lines: [String] = []
        lines.append("MyStuff – List: \(list.name)")
        let trimmedNotes = list.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            lines.append("")
            lines.append(trimmedNotes)
        }
        if !itemsInList.isEmpty {
            lines.append("")
            lines.append("Items:")
            for item in itemsInList {
                var parts: [String] = [item.name]
                if let catName = session.categories.categories.first(where: { $0.id == item.categoryId })?.name {
                    parts.append("(\(catName))")
                }
                if !item.tags.isEmpty {
                    parts.append("[\(item.tags.joined(separator: ", "))]")
                }
                lines.append("• " + parts.joined(separator: " "))
            }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if itemsInList.isEmpty {
                    Section {
                        Text("No items in this list yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                } else {
                    ForEach(itemsInList) { item in
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
                                    .fontWeight(.medium)
                                HStack(spacing: 6) {
                                    if let catName = session.categories.categories.first(where: { $0.id == item.categoryId })?.name {
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
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedItem = item
                        }
                    }
                    .onDelete(perform: removeItems)
                }
            }
        }
        .navigationTitle(list.name)
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        showItemPicker = true
                    } label: {
                        Label("Add items", systemImage: "plus.circle")
                    }
                    Button {
                        showComboPicker = true
                    } label: {
                        Label("Add combos", systemImage: "square.grid.2x2")
                    }
                    ShareLink(item: shareText) {
                        Label("Share list", systemImage: "square.and.arrow.up")
                    }
                }
            }
            #else
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showItemPicker = true
                    } label: {
                        Label("Add items", systemImage: "plus.circle")
                    }
                    Button {
                        showComboPicker = true
                    } label: {
                        Label("Add combos", systemImage: "square.grid.2x2")
                    }
                    ShareLink(item: shareText) {
                        Label("Share list", systemImage: "square.and.arrow.up")
                    }
                }
            }
            #endif
        }
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item, onDismiss: { selectedItem = nil })
                .environmentObject(session)
        }
        .sheet(isPresented: $showItemPicker) {
            ItemSelectionView(
                list: list,
                allItems: inventory.items,
                categories: session.categories.categories,
                initiallySelectedIds: Set(itemsInList.map(\.id)),
                onDone: { items in
                    Task {
                        await session.lists.addItems(items, to: list)
                    }
                    showItemPicker = false
                },
                onCancel: {
                    showItemPicker = false
                }
            )
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
            .environmentObject(session)
        }
        .sheet(isPresented: $showComboPicker) {
            ComboPickerView(
                combos: session.combos.combos,
                onDone: { combos in
                    Task {
                        let allItems = session.inventory.items
                        for combo in combos {
                            let comboItems = session.combos.items(for: combo, from: allItems)
                            await session.lists.addItems(comboItems, to: list)
                        }
                    }
                    showComboPicker = false
                },
                onCancel: {
                    showComboPicker = false
                }
            )
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
            .environmentObject(session)
        }
        .task {
            await listsVM.load()
            await inventory.refresh()
        }
    }

    private func removeItems(at offsets: IndexSet) {
        let toRemove = offsets.map { itemsInList[$0] }
        Task {
            await listsVM.removeItems(toRemove, from: list)
        }
    }
}

