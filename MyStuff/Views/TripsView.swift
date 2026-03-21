import SwiftUI
import MapKit

struct TripsView: View {
    @EnvironmentObject var session: Session
    @State private var showAddTrip = false
    @State private var selectedTrip: Trip?
    @State private var editingTrip: Trip?
    @State private var tripPendingDelete: Trip?
    @State private var deletingTripId: String?

    private var tripsVM: TripsViewModel { session.trips }

    var body: some View {
        NavigationStack {
            Group {
                if tripsVM.isLoading && tripsVM.trips.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tripsVM.trips.isEmpty {
                    ContentUnavailableView(
                        "No Shooting Locations Yet",
                        systemImage: "map",
                        description: Text("Tap + to add your first location.")
                    )
                } else {
                    tripGrid
                }
            }
            .navigationTitle("Shooting Locations")
            .searchable(
                text: Binding(get: { tripsVM.searchText }, set: { tripsVM.searchText = $0 }),
                prompt: "Search locations"
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
                TripFormSheet(trip: nil) { name, description, wikiURL, tags, lat, lon in
                    Task { await tripsVM.addTrip(name: name, description: description, wikiURL: wikiURL, tags: tags, latitude: lat, longitude: lon) }
                }
            }
            .sheet(item: $editingTrip) { trip in
                TripFormSheet(trip: trip) { name, description, wikiURL, tags, lat, lon in
                    var updated = trip
                    updated.name = name
                    updated.description = description
                    updated.wikiURL = wikiURL
                    updated.tags = tags
                    updated.latitude = lat
                    updated.longitude = lon
                    Task { await tripsVM.updateTrip(updated) }
                }
            }
            .confirmationDialog(
                "Delete \"\(tripPendingDelete?.name ?? "")\"?",
                isPresented: Binding(
                    get: { tripPendingDelete != nil },
                    set: { if !$0 { tripPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let trip = tripPendingDelete else { return }
                    tripPendingDelete = nil
                    deletingTripId = trip.id
                    Task {
                        await tripsVM.deleteTrips([trip])
                        deletingTripId = nil
                    }
                }
                Button("Cancel", role: .cancel) { tripPendingDelete = nil }
            } message: {
                Text("This cannot be undone.")
            }
            .navigationDestination(item: $selectedTrip) { trip in
                TripDetailView(trip: trip)
                    .environment(\.layoutDirection, .rightToLeft)
                    .multilineTextAlignment(.leading)
            }
            .task { await tripsVM.load() }
            .refreshable { await tripsVM.load() }
        }
    }

    private static let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var tripGrid: some View {
        ScrollView {
            if let err = tripsVM.errorMessage {
                Text(err)
                    .foregroundStyle(.red)
                    .padding()
            }
            if tripsVM.filteredTrips.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No shooting locations match your search.")
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: Self.gridColumns, spacing: 16) {
                    ForEach(tripsVM.filteredTrips) { trip in
                        TripCardView(
                            trip: trip,
                            locations: tripsVM.locations(for: trip),
                            visits: tripsVM.visits(for: trip),
                            isDeleting: deletingTripId == trip.id,
                            onEdit: { editingTrip = trip },
                            onDelete: { tripPendingDelete = trip }
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { if deletingTripId != trip.id { selectedTrip = trip } }
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct TripCardView: View {
    let trip: Trip
    let locations: [TripLocation]
    let visits: [TripVisit]
    let isDeleting: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var detailsExpanded = false

    private var visitCount: Int { visits.count }
    private var hasExpandable: Bool { !locations.isEmpty || !visits.isEmpty }

    // All unique sighting names across all visits
    private var allSightingNames: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for visit in visits {
            for sighting in visit.sightings {
                let key = sighting.name.lowercased()
                if !key.isEmpty && !seen.contains(key) {
                    seen.insert(key)
                    result.append(sighting.name)
                }
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(trip.name)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !trip.description.isEmpty {
                    Text(trip.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Expandable section (locations + observations)
            if hasExpandable {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { detailsExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        if !locations.isEmpty {
                            Image(systemName: "mappin")
                                .font(.caption)
                            Text("\(locations.count) location\(locations.count == 1 ? "" : "s")")
                                .font(.caption)
                        }
                        if !visits.isEmpty {
                            if !locations.isEmpty {
                                Text("·").font(.caption).foregroundStyle(.tertiary)
                            }
                            Image(systemName: "camera")
                                .font(.caption)
                            Text("\(visitCount) sighting\(visitCount == 1 ? "" : "s")")
                                .font(.caption)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .rotationEffect(.degrees(detailsExpanded ? 90 : 0))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if detailsExpanded {
                    HStack(alignment: .top, spacing: 0) {
                        // Left column: locations
                        if !locations.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Locations")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 6)
                                    .padding(.bottom, 4)
                                ForEach(Array(locations.enumerated()), id: \.element.id) { idx, loc in
                                    HStack(spacing: 6) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.accentColor.opacity(0.15))
                                                .frame(width: 16, height: 16)
                                            Text("\(idx + 1)")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(Color.accentColor)
                                        }
                                        Text(loc.name)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    if idx < locations.count - 1 {
                                        Divider().padding(.leading, 34)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        if !locations.isEmpty && !allSightingNames.isEmpty {
                            Divider()
                        }

                        // Right column: observations
                        if !allSightingNames.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Observed")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 6)
                                    .padding(.bottom, 4)
                                ForEach(Array(allSightingNames.enumerated()), id: \.offset) { idx, sightingName in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color.green.opacity(0.5))
                                            .frame(width: 5, height: 5)
                                        Text(sightingName)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    if idx < allSightingNames.count - 1 {
                                        Divider().padding(.leading, 23)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    Divider()
                }
            }

            // Spacer pushes footer to bottom so all cards align
            Spacer(minLength: 0)

            // Footer: deleting indicator
            if isDeleting {
                Divider()
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .multilineTextAlignment(.leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .opacity(isDeleting ? 0.5 : 1)
        .contextMenu {
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct TripFormSheet: View {
    let trip: Trip?
    let onSave: (String, String, String, [String], Double?, Double?) -> Void

    @EnvironmentObject var session: Session
    @State private var name: String
    @State private var tags: [String]
    @State private var wikiURL = ""
    @State private var wikiSummary: WikiSummary?
    @State private var isFetchingWiki = false
    @State private var wikiTask: Task<Void, Never>?
    @State private var nameDebounceTask: Task<Void, Never>?

    // Map / place search
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedCoordinate: CLLocationCoordinate2D?

    @Environment(\.dismiss) private var dismiss

    init(trip: Trip?, onSave: @escaping (String, String, String, [String], Double?, Double?) -> Void) {
        self.trip = trip
        self.onSave = onSave
        _name = State(initialValue: trip?.name ?? "")
        _tags = State(initialValue: trip?.tags ?? [])
        _wikiURL = State(initialValue: trip?.wikiURL ?? "")
        if let desc = trip?.description, !desc.isEmpty {
            _wikiSummary = State(initialValue: WikiSummary(title: trip?.name ?? "", extract: desc, pageURL: nil, thumbnailURL: nil))
        }
        if let lat = trip?.latitude, let lon = trip?.longitude {
            _selectedCoordinate = State(initialValue: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Shooting location name", text: $name)
                        .onChange(of: name) { _, newValue in
                            if selectedCoordinate == nil {
                                searchText = newValue
                                scheduleSearch(query: newValue)
                            }
                            scheduleNameWikiFetch(name: newValue)
                        }
                }
                Section("Tags") {
                    TagChipsEditor(tags: $tags, suggestions: session.allTags)
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
                        Button("Clear location", role: .destructive) {
                            selectedCoordinate = nil
                            searchText = ""
                            searchResults = []
                        }
                        .font(.caption)
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
            }
            .formStyle(.grouped)
            .navigationTitle(trip == nil ? "New Shooting Location" : "Edit Shooting Location")
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
        .environment(\.layoutDirection, .leftToRight)
        .presentationDetents([.large])
    }

    // MARK: - Map preview

    @ViewBuilder
    private func mapPreview(coordinate: CLLocationCoordinate2D) -> some View {
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        Map(coordinateRegion: .constant(region), annotationItems: [TripFormAnnotation(coordinate: coordinate)]) { item in
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
        selectedCoordinate = item.placemark.coordinate
        if let itemName = item.name, name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = itemName
        }
        searchResults = []
        searchText = item.name ?? ""
        if wikiSummary == nil {
            scheduleWikiFetch(name: item.name ?? name)
        }
    }

    // MARK: - Wikipedia fetching

    private func scheduleNameWikiFetch(name: String) {
        guard wikiSummary == nil else { return }
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

private struct TripFormAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
