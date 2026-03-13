import SwiftUI

struct ListsView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService

    @State private var showAddSheet = false
    @State private var editingList: UserList?

    private var listsVM: ListsViewModel { session.lists }

    var body: some View {
        NavigationStack {
            Group {
                if listsVM.isLoading, listsVM.lists.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if listsVM.lists.isEmpty, listsVM.errorMessage == nil {
                    ContentUnavailableView {
                        Label("No lists", systemImage: "checklist")
                    } description: {
                        Text("Create a list to group items for a specific situation like trips or shoots.")
                    } actions: {
                        Button("New list") { showAddSheet = true }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let err = listsVM.errorMessage {
                            Section {
                                Text(err)
                                    .foregroundStyle(.red)
                            }
                        }
                        ForEach(listsVM.filteredLists) { list in
                            NavigationLink(value: list) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(list.name)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    if !list.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(list.notes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    let listItems = listsVM.items(for: list, from: session.inventory.items)
                                    if !listItems.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 4) {
                                                ForEach(listItems) { item in
                                                    ItemThumbnailView(
                                                        drive: session.drive,
                                                        photoId: item.photoIds.first,
                                                        size: 26,
                                                        cornerRadius: 5,
                                                        placeholderFont: .caption
                                                    )
                                                }
                                            }
                                        }
                                        .padding(.top, 2)
                                    }
                                }
                            }
                            .contextMenu {
                                Button {
                                    editingList = list
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    Task { await listsVM.deleteLists([list]) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { indexSet in
                            let listsToDelete = indexSet.map { listsVM.filteredLists[$0] }
                            Task {
                                await listsVM.deleteLists(listsToDelete)
                            }
                        }
                    }
                    .refreshable { await listsVM.load() }
                }
            }
            .navigationTitle("My Lists")
            .navigationDestination(for: UserList.self) { list in
                ListDetailView(list: list)
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        searchField
                        Button { showAddSheet = true } label: { Image(systemName: "plus") }
                            .help("New list")
                        UserAvatarMenuView()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        searchField
                        Button { showAddSheet = true } label: { Image(systemName: "plus") }
                            .help("New list")
                        UserAvatarMenuView()
                    }
                }
                #endif
            }
            .sheet(isPresented: $showAddSheet) {
                ListFormSheet(
                    mode: .add,
                    existingList: nil,
                    onSave: { name, notes in
                        Task { await listsVM.addList(name: name, notes: notes) }
                    },
                    onDismiss: { showAddSheet = false }
                )
            }
            .sheet(item: $editingList) { list in
                ListFormSheet(
                    mode: .edit,
                    existingList: list,
                    onSave: { name, notes in
                        var updated = list
                        updated.name = name
                        updated.notes = notes
                        Task { await listsVM.updateList(updated) }
                    },
                    onDismiss: { editingList = nil }
                )
            }
            .task {
                await listsVM.load()
                // Ensure inventory and combos are loaded so pickers in ListDetailView have data.
                if session.inventory.items.isEmpty {
                    await session.inventory.refresh()
                }
                if session.combos.combos.isEmpty {
                    await session.combos.load()
                }
            }
        }
    }

    private var searchField: some View {
        ZStack(alignment: .trailing) {
            TextField("Search lists", text: Binding(
                get: { listsVM.searchText },
                set: { listsVM.searchText = $0 }
            ))
            .padding(.leading, 8)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 120, maxWidth: 200)
            .help("Search lists by name or notes")
            #if os(iOS)
            .focusEffectDisabled()
            #endif
            if !listsVM.searchText.isEmpty {
                Button {
                    listsVM.searchText = ""
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

private enum ListFormMode {
    case add
    case edit
}

private struct ListFormSheet: View {
    let mode: ListFormMode
    let existingList: UserList?
    let onSave: (String, String) -> Void
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .labelsHidden()
                } header: {
                    Text("Name")
                }
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Use notes to capture goals or constraints for this list (e.g. \"Carry-on only\", \"Night photography gear\").")
                }
            }
            .formStyle(.grouped)
            .padding(24)
            #if os(macOS)
            .frame(width: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            #endif
            .navigationTitle(mode == .add ? "New list" : "Edit list")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .help("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }
                        onSave(trimmedName, notes.trimmingCharacters(in: .whitespacesAndNewlines))
                        onDismiss()
                    }
                    .help("Save")
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            if let list = existingList {
                name = list.name
                notes = list.notes
            }
        }
        .presentationDetents([.medium, .large])
    }
}

