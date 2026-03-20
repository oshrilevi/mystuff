import SwiftUI
import MapKit

struct TripLocationFormSheet: View {
    let location: TripLocation?
    let onSave: (String, String, [String], Double?, Double?) -> Void

    @State private var name: String
    @State private var description: String
    @State private var tags: [String]
    @State private var latitude: String
    @State private var longitude: String
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isManualCoordinates = false
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.0, longitude: 35.0),
        span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)
    )
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss

    init(location: TripLocation?, onSave: @escaping (String, String, [String], Double?, Double?) -> Void) {
        self.location = location
        self.onSave = onSave
        _name = State(initialValue: location?.name ?? "")
        _description = State(initialValue: location?.description ?? "")
        _tags = State(initialValue: location?.tags ?? [])
        let lat = location?.latitude
        let lon = location?.longitude
        _latitude = State(initialValue: lat.map { String($0) } ?? "")
        _longitude = State(initialValue: lon.map { String($0) } ?? "")
        if let lat, let lon {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            _selectedCoordinate = State(initialValue: coord)
            _mapRegion = State(initialValue: MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            ))
        }
    }

    private var parsedLatitude: Double? { Double(latitude) }
    private var parsedLongitude: Double? { Double(longitude) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Location name", text: $name)
                        .onChange(of: name) { _, newValue in
                            if !isManualCoordinates && selectedCoordinate == nil {
                                searchText = newValue
                                scheduleSearch(query: newValue)
                            }
                        }
                }
                Section("Description") {
                    TextField("Optional description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Tags") {
                    TagChipsEditor(tags: $tags, suggestions: session.allTags)
                }

                Section {
                    Toggle("Enter coordinates manually", isOn: $isManualCoordinates)
                } header: {
                    Text("Coordinates")
                }

                if isManualCoordinates {
                    Section {
                        HStack {
                            Text("Latitude")
                            Spacer()
                            TextField("e.g. 31.7683", text: $latitude)
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                        HStack {
                            Text("Longitude")
                            Spacer()
                            TextField("e.g. 35.2137", text: $longitude)
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                        if let lat = parsedLatitude, let lon = parsedLongitude {
                            mapPreview(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                        }
                    }
                } else {
                    Section("Search for a place") {
                        TextField("Place name or address", text: $searchText)
                            .onChange(of: searchText) { _, newValue in
                                scheduleSearch(query: newValue)
                            }
                        if !searchResults.isEmpty {
                            ForEach(searchResults, id: \.self) { item in
                                Button {
                                    selectMapItem(item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "Unknown")
                                            .foregroundStyle(.primary)
                                        if let subtitle = item.placemark.title, subtitle != item.name {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let coord = selectedCoordinate {
                        Section("Selected Location") {
                            mapPreview(coordinate: coord)
                            HStack {
                                Text("Lat: \(String(format: "%.5f", coord.latitude))")
                                Spacer()
                                Text("Lon: \(String(format: "%.5f", coord.longitude))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(location == nil ? "New Location" : "Edit Location")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let finalLat: Double?
                        let finalLon: Double?
                        if isManualCoordinates {
                            finalLat = parsedLatitude
                            finalLon = parsedLongitude
                        } else {
                            finalLat = selectedCoordinate?.latitude
                            finalLon = selectedCoordinate?.longitude
                        }
                        onSave(name.trimmingCharacters(in: .whitespaces), description, tags, finalLat, finalLon)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func mapPreview(coordinate: CLLocationCoordinate2D) -> some View {
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        Map(coordinateRegion: .constant(region), annotationItems: [AnnotationItem(coordinate: coordinate)]) { item in
            MapMarker(coordinate: item.coordinate, tint: .red)
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(false)
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            let search = MKLocalSearch(request: request)
            if let response = try? await search.start() {
                searchResults = Array(response.mapItems.prefix(5))
            }
        }
    }

    private func selectMapItem(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        selectedCoordinate = coord
        latitude = String(coord.latitude)
        longitude = String(coord.longitude)
        if let itemName = item.name, name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = itemName
        }
        searchResults = []
        searchText = item.name ?? ""
    }
}

private struct AnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
