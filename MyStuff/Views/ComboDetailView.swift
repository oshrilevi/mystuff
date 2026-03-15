import SwiftUI

struct ComboDetailView: View {
    @EnvironmentObject var session: Session

    let combo: Combo

    @State private var selectedItem: Item?
    @State private var showItemSelection = false

    private var combosVM: CombosViewModel { session.combos }
    private var inventory: InventoryViewModel { session.inventory }

    private var itemsInCombo: [Item] {
        combosVM.items(for: combo, from: inventory.items)
    }

    var body: some View {
        VStack(spacing: 0) {
            if itemsInCombo.isEmpty {
                ContentUnavailableView {
                    Label("No items in this combo yet.", systemImage: "tray")
                } actions: {
                    Button {
                        showItemSelection = true
                    } label: {
                        Label("Add items to this combo", systemImage: "plus")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(itemsInCombo) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                ItemThumbnailView(
                                    drive: session.drive,
                                    photoId: item.photoIds.first,
                                    size: 64,
                                    cornerRadius: 8,
                                    placeholderFont: .title2
                                )
                                .frame(width: 64, height: 64)
                                .clipped()

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
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
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItem = item
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    removeItem(item)
                                } label: {
                                    Label("Remove from combo", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
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

    private func removeItem(_ item: Item) {
        Task {
            await combosVM.removeItems([item], from: combo)
        }
    }
}

