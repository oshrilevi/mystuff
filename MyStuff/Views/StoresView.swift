import SwiftUI

struct StoresView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService
    @State private var showAdd = false
    @State private var editingStore: UserStore?

    private var storesVM: StoresViewModel { session.stores }

    private var sortedStores: [UserStore] {
        storesVM.stores.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if storesVM.isLoading, storesVM.stores.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if storesVM.stores.isEmpty, storesVM.errorMessage == nil {
                    ContentUnavailableView {
                        Label("No stores", systemImage: "cart")
                    } description: {
                        Text("Add a store to open it in the in-app browser and use \"Add this item\" from product pages.")
                    } actions: {
                        Button("Add store") { showAdd = true }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let err = storesVM.errorMessage {
                            Section {
                                Text(err).foregroundStyle(.red)
                            }
                        }
                        ForEach(sortedStores) { store in
                            HStack(spacing: 12) {
                                StoreIconView(store: store, size: 24)
                                Text(store.name)
                                Text(store.startURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .contentShape(Rectangle())
                            .onTapGesture { editingStore = store }
                        }
                        .onDelete(perform: deleteStores)
                    }
                    .refreshable { await storesVM.load() }
                }
            }
            .navigationTitle("Stores")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                        UserAvatarMenuView()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                        UserAvatarMenuView()
                    }
                }
                #endif
            }
            .sheet(isPresented: $showAdd) {
                StoreFormSheet(storesVM: storesVM, mode: .add, onDismiss: { showAdd = false })
            }
            .sheet(item: $editingStore) { store in
                StoreFormSheet(storesVM: storesVM, mode: .edit(store), onDismiss: { editingStore = nil })
            }
            .task { await storesVM.load() }
        }
    }

    private func deleteStores(at offsets: IndexSet) {
        let ids = offsets.map { sortedStores[$0].id }
        Task { await storesVM.deleteStores(ids: ids) }
    }
}

// MARK: - Add / Edit store form

enum StoreFormMode {
    case add
    case edit(UserStore)
}

private struct StoreFormSheet: View {
    let storesVM: StoresViewModel
    let mode: StoreFormMode
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var startURL: String = "https://"
    @State private var isSaving = false

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
                    TextField("URL", text: $startURL)
                        #if os(iOS)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        #endif
                        .labelsHidden()
                } header: {
                    Text("Start URL")
                }
            }
            .formStyle(.grouped)
            .padding(24)
            #if os(macOS)
            .frame(width: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            #endif
            .navigationTitle(mode.isAdd ? "New store" : "Edit store")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button("Save") {
                            save()
                        }
                        .disabled(!isValid)
                    }
                }
            }
            .onAppear {
                switch mode {
                case .add:
                    break
                case .edit(let store):
                    name = store.name
                    startURL = store.startURL
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var isValid: Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        let u = startURL.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !u.isEmpty else { return false }
        return URL(string: u).map { $0.scheme == "https" || $0.scheme == "http" } ?? false
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let u = startURL.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !u.isEmpty else { return }
        isSaving = true
        Task {
            switch mode {
            case .add:
                await storesVM.addStore(name: n, startURL: u, systemImage: "link")
            case .edit(let store):
                await storesVM.updateStore(id: store.id, name: n, startURL: u, systemImage: store.systemImage)
            }
            isSaving = false
            onDismiss()
        }
    }
}

extension StoreFormMode {
    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
}
