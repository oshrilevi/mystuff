import SwiftUI

struct TripLocationsManagementView: View {
    @EnvironmentObject var session: Session
    @State private var showAddLocation = false
    @State private var editingLocation: TripLocation?
    @State private var searchText = ""

    private var tripsVM: TripsViewModel { session.trips }

    private var sortedLocations: [TripLocation] {
        let all = tripsVM.tripLocations
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter {
            $0.name.lowercased().contains(q) ||
            $0.description.lowercased().contains(q) ||
            $0.tags.joined(separator: " ").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if tripsVM.isLoading && tripsVM.tripLocations.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tripsVM.tripLocations.isEmpty {
                    ContentUnavailableView(
                        "No Locations",
                        systemImage: "mappin.slash",
                        description: Text("Add shared locations to reuse across trips.")
                    )
                } else {
                    List {
                        if let err = tripsVM.errorMessage {
                            Section {
                                Text(err).foregroundStyle(.red)
                            }
                        }
                        ForEach(sortedLocations) { loc in
                            locationRow(loc)
                                .contentShape(Rectangle())
                                .onTapGesture { editingLocation = loc }
                        }
                        .onDelete { offsets in
                            let ids = Set(offsets.map { sortedLocations[$0].id })
                            Task { await tripsVM.deleteTripLocations(ids: ids) }
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.inset)
                    #endif
                }
            }
            .navigationTitle("Trip Locations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Search locations")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddLocation = true } label: { Image(systemName: "plus") }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddLocation = true } label: { Image(systemName: "plus") }
                        .help("Add location")
                }
                #endif
            }
            .sheet(isPresented: $showAddLocation) {
                TripLocationFormSheet(location: nil) { name, description, tags, lat, lon in
                    Task { await tripsVM.addTripLocation(name: name, description: description, tags: tags, latitude: lat, longitude: lon) }
                }
            }
            .sheet(item: $editingLocation) { loc in
                TripLocationFormSheet(location: loc) { name, description, tags, lat, lon in
                    var updated = loc
                    updated.name = name
                    updated.description = description
                    updated.tags = tags
                    updated.latitude = lat
                    updated.longitude = lon
                    Task { await tripsVM.updateTripLocation(updated) }
                }
            }
            .task { await tripsVM.load() }
        }
    }

    private func locationRow(_ loc: TripLocation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(loc.name)
                .font(.headline)
            if !loc.description.isEmpty {
                Text(loc.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !loc.tags.isEmpty {
                Text(loc.tags.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let lat = loc.latitude, let lon = loc.longitude {
                Text(String(format: "%.4f, %.4f", lat, lon))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
