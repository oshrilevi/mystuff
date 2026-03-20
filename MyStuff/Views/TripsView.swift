import SwiftUI

struct TripsView: View {
    @EnvironmentObject var session: Session
    @State private var showAddTrip = false
    @State private var selectedTrip: Trip?

    private var tripsVM: TripsViewModel { session.trips }

    var body: some View {
        NavigationStack {
            Group {
                if tripsVM.isLoading && tripsVM.trips.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tripsVM.trips.isEmpty {
                    ContentUnavailableView(
                        "No Trips Yet",
                        systemImage: "map",
                        description: Text("Tap + to add your first trip.")
                    )
                } else {
                    tripList
                }
            }
            .navigationTitle("My Trips")
            .searchable(
                text: Binding(get: { tripsVM.searchText }, set: { tripsVM.searchText = $0 }),
                prompt: "Search trips"
            )
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { showAddTrip = true } label: { Image(systemName: "plus") }
                            .help("Add trip")
                        UserAvatarMenuView()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button { showAddTrip = true } label: { Image(systemName: "plus") }
                            .help("Add trip")
                        UserAvatarMenuView()
                    }
                }
                #endif
            }
            .sheet(isPresented: $showAddTrip) {
                TripFormSheet(trip: nil) { name, description, tags in
                    Task { await tripsVM.addTrip(name: name, description: description, tags: tags) }
                }
            }
            .navigationDestination(item: $selectedTrip) { trip in
                TripDetailView(trip: trip)
            }
            .task { await tripsVM.load() }
            .refreshable { await tripsVM.load() }
        }
    }

    private var tripList: some View {
        List {
            if let err = tripsVM.errorMessage {
                Section {
                    Text(err).foregroundStyle(.red)
                }
            }
            ForEach(tripsVM.filteredTrips) { trip in
                TripRowView(
                    trip: trip,
                    locations: tripsVM.locations(for: trip),
                    visitCount: tripsVM.visits(for: trip).count
                )
                .contentShape(Rectangle())
                .onTapGesture { selectedTrip = trip }
            }
            .onDelete { offsets in
                let toDelete = offsets.map { tripsVM.filteredTrips[$0] }
                Task { await tripsVM.deleteTrips(toDelete) }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }
}

private struct TripRowView: View {
    let trip: Trip
    let locations: [TripLocation]
    let visitCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack {
                Text(trip.name)
                    .font(.headline)
                Spacer()
                if visitCount > 0 {
                    Label("\(visitCount)", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Description
            if !trip.description.isEmpty {
                Text(trip.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Locations strip
            if !locations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(locations.enumerated()), id: \.element.id) { idx, loc in
                            HStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.15))
                                        .frame(width: 18, height: 18)
                                    Text("\(idx + 1)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Color.accentColor)
                                }
                                Text(loc.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            if idx < locations.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            // Tags
            if !trip.tags.isEmpty {
                TagChipsView(tags: trip.tags)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TripFormSheet: View {
    let trip: Trip?
    let onSave: (String, String, [String]) -> Void

    @State private var name: String
    @State private var description: String
    @State private var tags: [String]
    @Environment(\.dismiss) private var dismiss

    init(trip: Trip?, onSave: @escaping (String, String, [String]) -> Void) {
        self.trip = trip
        self.onSave = onSave
        _name = State(initialValue: trip?.name ?? "")
        _description = State(initialValue: trip?.description ?? "")
        _tags = State(initialValue: trip?.tags ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Trip name", text: $name)
                }
                Section("Description") {
                    TextField("Optional description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Tags") {
                    TagChipsEditor(tags: $tags)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(trip == nil ? "New Trip" : "Edit Trip")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name.trimmingCharacters(in: .whitespaces), description, tags)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
