import SwiftUI

struct LocationsView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService
    @State private var newLocationName = ""
    @State private var showAdd = false
    @State private var editingLocation: Location?

    private var locationsVM: LocationsViewModel { session.locations }

    private var sortedLocations: [Location] {
        locationsVM.locations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if locationsVM.isLoading, locationsVM.locations.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let err = locationsVM.errorMessage {
                            Section {
                                Text(err).foregroundStyle(.red)
                            }
                        }
                        ForEach(sortedLocations) { loc in
                            HStack(spacing: 12) {
                                Text(loc.name)
                                if locationsVM.defaultLocationId == loc.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .contentShape(Rectangle())
                            .onTapGesture { editingLocation = loc }
                        }
                        .onDelete(perform: deleteLocations)
                    }
                    .refreshable { await locationsVM.load() }
                }
            }
            .navigationTitle("Locations")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                            .help("Add location")
                        UserAvatarMenuView()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                            .help("Add location")
                        UserAvatarMenuView()
                    }
                }
                #endif
            }
            .alert("New location", isPresented: $showAdd) {
                TextField("Name", text: $newLocationName)
                Button("Cancel", role: .cancel) { newLocationName = "" }
                Button("Add") {
                    let name = newLocationName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        Task { await locationsVM.addLocation(name: name) }
                        newLocationName = ""
                    }
                }
            } message: {
                Text("Enter location name")
            }
            .sheet(item: $editingLocation) { loc in
                EditLocationSheet(
                    location: loc,
                    locationsVM: locationsVM,
                    onDismiss: { editingLocation = nil }
                )
            }
            .task { await locationsVM.load() }
        }
    }

    private func deleteLocations(at offsets: IndexSet) {
        let ids = offsets.map { sortedLocations[$0].id }
        Task { await locationsVM.deleteLocation(ids: ids) }
    }
}

private struct EditLocationSheet: View {
    let location: Location
    let locationsVM: LocationsViewModel
    let onDismiss: () -> Void

    @State private var name: String

    init(location: Location, locationsVM: LocationsViewModel, onDismiss: @escaping () -> Void) {
        self.location = location
        self.locationsVM = locationsVM
        self.onDismiss = onDismiss
        _name = State(initialValue: location.name)
    }

    private var isDefault: Bool { locationsVM.defaultLocationId == location.id }

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
                    if isDefault {
                        HStack {
                            Text("Default location for new items")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Set as default location") {
                            locationsVM.setDefaultLocation(id: location.id)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(24)
            .frame(width: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .navigationTitle("Edit location")
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
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            Task {
                                await locationsVM.updateLocation(id: location.id, name: trimmed)
                            }
                        }
                        onDismiss()
                    }
                    .help("Save")
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
