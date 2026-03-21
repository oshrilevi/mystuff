import SwiftUI
import MapKit
import PhotosUI

// MARK: - Description Source

private enum DescriptionSource: String, CaseIterable {
    case wikipedia = "Wikipedia"
    case manual    = "Manual"
}

// MARK: - Form Sheet

struct TripLocationFormSheet: View {
    let location: TripLocation?
    let onSave: (String, String, String, [String], Double?, Double?, LocationType, [String]) -> Void

    @State private var name: String
    @State private var type: LocationType
    @State private var tags: [String]
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var photoIds: [String]
    @State private var pendingItems: [PhotosPickerItem] = []

    // Description
    @State private var descriptionSource: DescriptionSource
    @State private var manualDescription: String

    // Wikipedia
    @State private var wikiURL = ""
    @State private var wikiSummary: WikiSummary? = nil
    @State private var isFetchingWiki = false
    @State private var wikiTask: Task<Void, Never>?
    @State private var nameDebounceTask: Task<Void, Never>?

    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss

    init(location: TripLocation?, initialCoordinate: CLLocationCoordinate2D? = nil,
         onSave: @escaping (String, String, String, [String], Double?, Double?, LocationType, [String]) -> Void) {
        self.location = location
        self.onSave = onSave
        _name = State(initialValue: location?.name ?? "")
        _type = State(initialValue: location?.type ?? .natureReserve)
        _tags = State(initialValue: location?.tags ?? [])
        _wikiURL = State(initialValue: location?.wikiURL ?? "")
        _photoIds = State(initialValue: location?.photoIds ?? [])

        if let lat = location?.latitude, let lon = location?.longitude {
            _selectedCoordinate = State(initialValue: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        } else if let coord = initialCoordinate {
            _selectedCoordinate = State(initialValue: coord)
        }

        let existingDesc = location?.description ?? ""
        let hasWikiURL   = !(location?.wikiURL ?? "").isEmpty

        // If there's a description but no wiki URL, default to manual mode
        if !existingDesc.isEmpty && !hasWikiURL {
            _descriptionSource  = State(initialValue: .manual)
            _manualDescription  = State(initialValue: existingDesc)
            _wikiSummary        = State(initialValue: nil)
        } else {
            _descriptionSource  = State(initialValue: .wikipedia)
            _manualDescription  = State(initialValue: "")
            // Seed the wiki summary so the existing description is shown
            if !existingDesc.isEmpty {
                _wikiSummary = State(initialValue: WikiSummary(
                    title: location?.name ?? "", extract: existingDesc, pageURL: nil, thumbnailURL: nil))
            } else {
                _wikiSummary = State(initialValue: nil)
            }
        }
    }

    // The description that will actually be saved
    private var activeDescription: String {
        switch descriptionSource {
        case .wikipedia: return wikiSummary?.extract ?? ""
        case .manual:    return manualDescription
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Name
                Section("Name") {
                    TextField("Location name", text: $name)
                        .onChange(of: name) { _, newValue in
                            if selectedCoordinate == nil {
                                searchText = newValue
                                scheduleSearch(query: newValue)
                            }
                            // Only auto-fetch wiki when in wiki mode and no description yet
                            if descriptionSource == .wikipedia && wikiSummary == nil {
                                scheduleNameWikiFetch(name: newValue)
                            }
                        }
                }

                // MARK: Type
                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(LocationType.sorted, id: \.self) { t in
                            Label(t.rawValue, systemImage: t.systemImage).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // MARK: About
                Section {
                    Picker("Source", selection: $descriptionSource) {
                        ForEach(DescriptionSource.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if descriptionSource == .wikipedia {
                        wikipediaContent
                    } else {
                        TextEditor(text: $manualDescription)
                            .frame(minHeight: 100)
                    }
                } header: {
                    Text("About")
                }

                // MARK: Search for a place
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

                // MARK: Selected location preview
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

                // MARK: Tags
                Section("Tags") {
                    TagChipsEditor(tags: $tags, suggestions: session.allTags)
                }

                // MARK: Photos
                Section("Photos") {
                    PhotosPicker(selection: $pendingItems, maxSelectionCount: 10, matching: .images) {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                    }
                    if !photoIds.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(photoIds, id: \.self) { id in
                                    ZStack(alignment: .topTrailing) {
                                                        PHAssetThumbnail(identifier: id, size: 72)
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                        Button {
                                            photoIds.removeAll { $0 == id }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                                .font(.system(size: 18))
                                        }
                                        .buttonStyle(.plain)
                                        .offset(x: 6, y: -6)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
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
                        onSave(
                            name.trimmingCharacters(in: .whitespaces),
                            activeDescription,
                            wikiURL,
                            tags,
                            selectedCoordinate?.latitude,
                            selectedCoordinate?.longitude,
                            type,
                            photoIds
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: pendingItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                let itemsToSave = newItems
                pendingItems = []
                Task {
                    for item in itemsToSave {
                        if let filename = await PhotoStorageService.save(item: item) {
                            photoIds.append(filename)
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Wikipedia sub-view

    @ViewBuilder
    private var wikipediaContent: some View {
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
    }

    // MARK: - Map preview

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

    // MARK: - Search

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
        if let itemName = item.name, name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = itemName
        }
        searchResults = []
        searchText = item.name ?? ""
        // Only fetch wiki if in wiki mode and nothing found yet
        if descriptionSource == .wikipedia && wikiSummary == nil {
            scheduleWikiFetch(name: item.name ?? name)
        }
    }

    // MARK: - Wikipedia fetching

    /// Auto-triggered by name changes — only when no description exists yet.
    private func scheduleNameWikiFetch(name: String) {
        guard wikiSummary == nil else { return }   // skip if we already have content
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
}

// MARK: - Helpers

private struct AnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
