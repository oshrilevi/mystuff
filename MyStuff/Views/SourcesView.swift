import SwiftUI

struct SourcesView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService
    @State private var showAdd = false
    @State private var editingSource: UserSource?

    private var sourcesVM: SourcesViewModel { session.sources }

    private var sortedSources: [UserSource] {
        sourcesVM.sources.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sourcesVM.isLoading, sourcesVM.sources.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sourcesVM.sources.isEmpty, sourcesVM.errorMessage == nil {
                    ContentUnavailableView {
                        Label("No sources", systemImage: "link")
                    } description: {
                        Text("Add a source to open it in the in-app browser.")
                    } actions: {
                        Button("Add source") { showAdd = true }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let err = sourcesVM.errorMessage {
                            Section {
                                Text(err).foregroundStyle(.red)
                            }
                        }
                        ForEach(sortedSources) { source in
                            HStack(spacing: 12) {
                                Image(systemName: "link")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .center)
                                Text(source.name)
                                Text(source.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .contentShape(Rectangle())
                            .onTapGesture { editingSource = source }
                        }
                        .onDelete(perform: deleteSources)
                    }
                    .refreshable { await sourcesVM.load() }
                }
            }
            .navigationTitle("Sources")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                            .help("Add source")
                        UserAvatarMenuView()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                            .help("Add source")
                        UserAvatarMenuView()
                    }
                }
                #endif
            }
            .sheet(isPresented: $showAdd) {
                SourceFormSheet(sourcesVM: sourcesVM, mode: .add, onDismiss: { showAdd = false })
            }
            .sheet(item: $editingSource) { source in
                SourceFormSheet(sourcesVM: sourcesVM, mode: .edit(source), onDismiss: { editingSource = nil })
            }
            .task { await sourcesVM.load() }
        }
    }

    private func deleteSources(at offsets: IndexSet) {
        let ids = offsets.map { sortedSources[$0].id }
        Task { await sourcesVM.deleteSources(ids: ids) }
    }
}

// MARK: - Add / Edit source form

enum SourceFormMode {
    case add
    case edit(UserSource)
}

private struct SourceFormSheet: View {
    let sourcesVM: SourcesViewModel
    let mode: SourceFormMode
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var url: String = "https://"
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
                    TextField("URL", text: $url)
                        #if os(iOS)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        #endif
                        .labelsHidden()
                } header: {
                    Text("URL")
                }
            }
            .formStyle(.grouped)
            .padding(24)
            #if os(macOS)
            .frame(width: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            #endif
            .navigationTitle(mode.isAdd ? "New source" : "Edit source")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .help("Cancel")
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
                        .help("Save")
                        .disabled(!isValid)
                    }
                }
            }
            .onAppear {
                switch mode {
                case .add:
                    break
                case .edit(let source):
                    name = source.name
                    url = source.url
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var isValid: Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        let u = url.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !u.isEmpty else { return false }
        return URL(string: u).map { $0.scheme == "https" || $0.scheme == "http" } ?? false
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let u = url.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !u.isEmpty else { return }
        isSaving = true
        Task {
            switch mode {
            case .add:
                await sourcesVM.addSource(name: n, url: u)
            case .edit(let source):
                await sourcesVM.updateSource(id: source.id, name: n, url: u)
            }
            isSaving = false
            onDismiss()
        }
    }
}

extension SourceFormMode {
    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
}
