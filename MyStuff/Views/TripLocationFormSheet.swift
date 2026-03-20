import SwiftUI
import MapKit

struct TripLocationFormSheet: View {
    let location: TripLocation?
    let onSave: (String, String, String, [String], Double?, Double?) -> Void

    @State private var name: String
    @State private var tags: [String]
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedCoordinate: CLLocationCoordinate2D?

    // Wikipedia
    @State private var wikiURL = ""
    @State private var wikiSummary: WikiSummary? = nil
    @State private var isFetchingWiki = false
    @State private var wikiTask: Task<Void, Never>?
    @State private var nameDebounceTask: Task<Void, Never>?

    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss

    init(location: TripLocation?, initialCoordinate: CLLocationCoordinate2D? = nil, onSave: @escaping (String, String, String, [String], Double?, Double?) -> Void) {
        self.location = location
        self.onSave = onSave
        _name = State(initialValue: location?.name ?? "")
        _tags = State(initialValue: location?.tags ?? [])
        _wikiURL = State(initialValue: location?.wikiURL ?? "")
        if let lat = location?.latitude, let lon = location?.longitude {
            _selectedCoordinate = State(initialValue: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        } else if let coord = initialCoordinate {
            _selectedCoordinate = State(initialValue: coord)
        }
        if let desc = location?.description, !desc.isEmpty {
            _wikiSummary = State(initialValue: WikiSummary(title: location?.name ?? "", extract: desc, pageURL: nil))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Location name", text: $name)
                        .onChange(of: name) { _, newValue in
                            if selectedCoordinate == nil {
                                searchText = newValue
                                scheduleSearch(query: newValue)
                            }
                            scheduleNameWikiFetch(name: newValue)
                        }
                }

                Section {
                    HStack {
                        TextField("Wikipedia URL", text: $wikiURL)
                            .onSubmit { fetchFromURL() }
                        if isFetchingWiki {
                            ProgressView()
                        } else {
                            Button {
                                if !wikiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    fetchFromURL()
                                } else {
                                    scheduleWikiFetch(name: name)
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let wiki = wikiSummary {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(wiki.title)
                                .font(.subheadline.bold())
                            Text(wiki.extract)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let url = wiki.pageURL {
                                Link("Open in Wikipedia", destination: url)
                                    .font(.caption)
                            }
                        }
                    } else if !isFetchingWiki {
                        Text("No Wikipedia article found.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } header: {
                    Text("About")
                }

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

                Section("Tags") {
                    TagChipsEditor(tags: $tags, suggestions: session.allTags)
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
                        onSave(
                            name.trimmingCharacters(in: .whitespaces),
                            wikiSummary?.extract ?? "",
                            wikiURL,
                            tags,
                            selectedCoordinate?.latitude,
                            selectedCoordinate?.longitude
                        )
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

    private func scheduleNameWikiFetch(name: String) {
        nameDebounceTask?.cancel()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        nameDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            scheduleWikiFetch(name: name)
        }
    }

    private func fetchFromURL() {
        let url = wikiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        wikiTask?.cancel()
        isFetchingWiki = true
        wikiSummary = nil
        wikiTask = Task {
            let result = await WikipediaService.fetchSummary(wikiURL: url)
            guard !Task.isCancelled else { return }
            isFetchingWiki = false
            wikiSummary = result
            if let pageURL = result?.pageURL {
                wikiURL = pageURL.absoluteString
            }
        }
    }

    private func scheduleWikiFetch(name: String) {
        wikiTask?.cancel()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isFetchingWiki = true
        wikiSummary = nil
        wikiTask = Task {
            let result = await WikipediaService.fetchSummary(name: name)
            guard !Task.isCancelled else { return }
            isFetchingWiki = false
            wikiSummary = result
            if let pageURL = result?.pageURL {
                wikiURL = pageURL.absoluteString
            }
        }
    }

    private func selectMapItem(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        selectedCoordinate = coord
        if let itemName = item.name, name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = itemName
        }
        searchResults = []
        searchText = item.name ?? ""
        scheduleWikiFetch(name: item.name ?? name)
    }
}

private struct AnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
