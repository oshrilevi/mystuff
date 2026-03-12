import SwiftUI

struct ListDetailView: View {
    @EnvironmentObject var session: Session

    let list: UserList

    @State private var selectedItem: Item?

    private var listsVM: ListsViewModel { session.lists }
    private var inventory: InventoryViewModel { session.inventory }

    private var itemsInList: [Item] {
        listsVM.items(for: list, from: inventory.items)
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
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.2))
                                if let fileId = item.photoIds.first {
                                    DriveImageView(
                                        drive: session.drive,
                                        fileId: fileId,
                                        contentMode: .fit
                                    )
                                    .frame(width: 44, height: 44)
                                    .clipped()
                                    .cornerRadius(8)
                                } else {
                                    Image(systemName: "photo")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 44, height: 44)

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
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item, onDismiss: { selectedItem = nil })
                .environmentObject(session)
        }
    }

    private func removeItems(at offsets: IndexSet) {
        let toRemove = offsets.map { itemsInList[$0] }
        Task {
            await listsVM.removeItems(toRemove, from: list)
        }
    }
}

