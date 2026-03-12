import SwiftUI

struct CombosView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService

    @State private var showAddSheet = false
    @State private var editingCombo: Combo?
    @State private var selectedItem: Item?
    @State private var combosPendingDeletion: [Combo] = []
    @State private var showDeleteConfirmation = false

    private var combosVM: CombosViewModel { session.combos }
    private var inventory: InventoryViewModel { session.inventory }

    var body: some View {
        NavigationStack {
            Group {
                if combosVM.isLoading, combosVM.combos.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if combosVM.combos.isEmpty, combosVM.errorMessage == nil {
                    ContentUnavailableView {
                        Label("No combos", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Create a combo to reuse groups of items that go together, like camera + lens + batteries.")
                    } actions: {
                        Button("New combo") { showAddSheet = true }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let err = combosVM.errorMessage {
                            Section {
                                Text(err)
                                    .foregroundStyle(.red)
                            }
                        }
                        ForEach(combosVM.filteredCombos) { combo in
                            NavigationLink(value: combo) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(combo.name)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    let itemsInCombo = combosVM.items(for: combo, from: inventory.items)
                                    if !itemsInCombo.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(itemsInCombo) { item in
                                                    ItemThumbnailView(
                                                        drive: session.drive,
                                                        photoId: item.photoIds.first,
                                                        size: 44,
                                                        cornerRadius: 8,
                                                        placeholderFont: .title2
                                                    )
                                                    .onTapGesture {
                                                        selectedItem = item
                                                    }
                                                }
                                            }
                                            .padding(.top, 4)
                                        }
                                    }
                                }
                            }
                            .contextMenu {
                                Button {
                                    editingCombo = combo
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    combosPendingDeletion = [combo]
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { indexSet in
                            let combosToDelete = indexSet.map { combosVM.filteredCombos[$0] }
                            combosPendingDeletion = combosToDelete
                            showDeleteConfirmation = true
                        }
                    }
                    .refreshable { await combosVM.load() }
                }
            }
            .navigationTitle("Combos")
            .navigationDestination(for: Combo.self) { combo in
                ComboDetailView(combo: combo)
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        searchField
                        Button { showAddSheet = true } label: { Image(systemName: "plus") }
                            .help("New combo")
                        UserAvatarMenuView()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        searchField
                        Button { showAddSheet = true } label: { Image(systemName: "plus") }
                            .help("New combo")
                        UserAvatarMenuView()
                    }
                }
                #endif
            }
            .sheet(isPresented: $showAddSheet) {
                ComboFormSheet(
                    mode: .add,
                    existingCombo: nil,
                    onSave: { name, notes in
                        Task { await combosVM.addCombo(name: name, notes: notes) }
                    },
                    onDismiss: { showAddSheet = false }
                )
            }
            .sheet(item: $editingCombo) { combo in
                ComboFormSheet(
                    mode: .edit,
                    existingCombo: combo,
                    onSave: { name, notes in
                        var updated = combo
                        updated.name = name
                        updated.notes = notes
                        Task { await combosVM.updateCombo(updated) }
                    },
                    onDismiss: { editingCombo = nil }
                )
            }
            .sheet(item: $selectedItem) { item in
                ItemDetailView(
                    item: item,
                    allowEditing: false,
                    allowDeleting: false,
                    onDismiss: { selectedItem = nil }
                )
                .environmentObject(session)
            }
            .confirmationDialog(
                "Delete combo\(combosPendingDeletion.count > 1 ? "s" : "")?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                if !combosPendingDeletion.isEmpty {
                    if combosPendingDeletion.count == 1 {
                        let name = combosPendingDeletion[0].name
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let display = trimmed.isEmpty ? "this combo" : "\"\(trimmed.count > 75 ? String(trimmed.prefix(75)) + "…" : trimmed)\""
                        Button("Delete \(display)", role: .destructive) {
                            let toDelete = combosPendingDeletion
                            combosPendingDeletion = []
                            Task {
                                await combosVM.deleteCombos(toDelete)
                            }
                        }
                    } else {
                        Button("Delete \(combosPendingDeletion.count) combos", role: .destructive) {
                            let toDelete = combosPendingDeletion
                            combosPendingDeletion = []
                            Task {
                                await combosVM.deleteCombos(toDelete)
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    combosPendingDeletion = []
                }
            } message: {
                Text("This cannot be undone. The selected combo\(combosPendingDeletion.count > 1 ? "s" : "") will be removed.")
            }
            .task {
                await combosVM.load()
                if inventory.items.isEmpty {
                    await inventory.refresh()
                }
            }
        }
    }

    private var searchField: some View {
        ZStack(alignment: .trailing) {
            TextField("Search combos", text: Binding(
                get: { combosVM.searchText },
                set: { combosVM.searchText = $0 }
            ))
            .padding(.leading, 8)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 120, maxWidth: 200)
            .help("Search combos by name or notes")
            #if os(iOS)
            .focusEffectDisabled()
            #endif
            if !combosVM.searchText.isEmpty {
                Button {
                    combosVM.searchText = ""
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

private enum ComboFormMode {
    case add
    case edit
}

private struct ComboFormSheet: View {
    let mode: ComboFormMode
    let existingCombo: Combo?
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
                    Text("Use notes to describe when to use this combo (e.g. \"Travel kit\", \"Studio portrait setup\").")
                }
            }
            .formStyle(.grouped)
            .padding(24)
            #if os(macOS)
            .frame(width: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            #endif
            .navigationTitle(mode == .add ? "New combo" : "Edit combo")
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
            if let combo = existingCombo {
                name = combo.name
                notes = combo.notes
            }
        }
        .presentationDetents([.medium, .large])
    }
}

