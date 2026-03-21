import SwiftUI
import MapKit

struct TripLocationPickerView: View {
    let existingLocationIds: [String]
    let tripsVM: TripsViewModel
    let onSelect: (TripLocation) -> Void

    @State private var searchText = ""
    @State private var showCreateLocation = false
    @Environment(\.dismiss) private var dismiss

    private var availableLocations: [TripLocation] {
        let existing = Set(existingLocationIds)
        let all = tripsVM.tripLocations
            .filter { !existing.contains($0.id) }
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
                if availableLocations.isEmpty && searchText.isEmpty {
                    ContentUnavailableView(
                        "No Locations Available",
                        systemImage: "mappin.slash",
                        description: Text("Create a new location to add to this trip.")
                    )
                } else {
                    List {
                        ForEach(availableLocations) { loc in
                            Button {
                                onSelect(loc)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(loc.name)
                                        .foregroundStyle(.primary)
                                    if !loc.description.isEmpty {
                                        Text(loc.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    if !loc.tags.isEmpty {
                                        Text(loc.tags.joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let lat = loc.latitude, let lon = loc.longitude {
                                        Text(String(format: "%.4f, %.4f", lat, lon))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Add Location")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Search locations")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateLocation = true
                    } label: {
                        Label("New Location", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateLocation) {
                TripLocationFormSheet(location: nil) { name, description, wikiURL, tags, lat, lon, type in
                    Task {
                        await tripsVM.addTripLocation(name: name, description: description, wikiURL: wikiURL, tags: tags, latitude: lat, longitude: lon, type: type)
                        if let created = tripsVM.tripLocations.last(where: { $0.name == name }) {
                            onSelect(created)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
