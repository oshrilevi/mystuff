import SwiftUI

struct ComboDetailView: View {
    @EnvironmentObject var session: Session

    let combo: Combo

    @State private var selectedItem: Item?
    @State private var showItemSelection = false
    #if os(macOS)
    @State private var hoveredItemId: String?
    #endif

    private var combosVM: CombosViewModel { session.combos }
    private var inventory: InventoryViewModel { session.inventory }

    private var itemsInCombo: [Item] {
        combosVM.items(for: combo, from: inventory.items)
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if itemsInCombo.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Text("No items in this combo yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                showItemSelection = true
                            } label: {
                                Label("Add items to this combo", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                    }
                } else {
                    ForEach(itemsInCombo) { item in
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
                            #if os(macOS)
                            Button {
                                Task {
                                    await combosVM.removeItems([item], from: combo)
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .opacity(hoveredItemId == item.id ? 1 : 0)
                            #endif
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedItem = item
                        }
                        #if os(macOS)
                        .onHover { isHovering in
                            if isHovering {
                                hoveredItemId = item.id
                            } else if hoveredItemId == item.id {
                                hoveredItemId = nil
                            }
                        }
                        #endif
                    }
                    .onDelete(perform: removeItems)
                }
            }
        }
        .navigationTitle(combo.name)
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showItemSelection = true
                } label: {
                    Label("Add items", systemImage: "plus")
                }
            }
            #else
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showItemSelection = true
                } label: {
                    Label("Add items", systemImage: "plus")
                }
            }
            #endif
        }
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item, onDismiss: { selectedItem = nil })
                .environmentObject(session)
        }
        .sheet(isPresented: $showItemSelection) {
            ComboItemSelectionView(
                combo: combo,
                initiallySelectedIds: Set(itemsInCombo.map(\.id)),
                onDone: { items in
                    Task {
                        await combosVM.addItems(items, to: combo)
                    }
                    showItemSelection = false
                },
                onCancel: {
                    showItemSelection = false
                }
            )
            .environmentObject(session)
        }
    }

    private func removeItems(at offsets: IndexSet) {
        let toRemove = offsets.map { itemsInCombo[$0] }
        Task {
            await combosVM.removeItems(toRemove, from: combo)
        }
    }
}

