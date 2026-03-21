import SwiftUI

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
                TripFormSheet(trip: nil) { name, description, wikiURL, tags in
                    Task { await tripsVM.addTrip(name: name, description: description, wikiURL: wikiURL, tags: tags) }
                }
            }
            .sheet(item: $editingTrip) { trip in
                TripFormSheet(trip: trip) { name, description, wikiURL, tags in
                    var updated = trip
                    updated.name = name
                    updated.description = description
                    updated.wikiURL = wikiURL
                    updated.tags = tags
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
                            visitCount: tripsVM.visits(for: trip).count,
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
    let visitCount: Int
    let isDeleting: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var locationsExpanded = false

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

            // Expandable locations section
            if !locations.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { locationsExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin")
                            .font(.caption)
                        Text("\(locations.count) location\(locations.count == 1 ? "" : "s")")
                            .font(.caption)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .rotationEffect(.degrees(locationsExpanded ? 90 : 0))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if locationsExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(locations.enumerated()), id: \.element.id) { idx, loc in
                            HStack(spacing: 8) {
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
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            if idx < locations.count - 1 {
                                Divider().padding(.trailing, 38)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    Divider()
                }
            }

            // Spacer pushes footer to bottom so all cards align
            Spacer(minLength: 0)

            // Footer: sightings count (no action button — use right-click)
            if visitCount > 0 || isDeleting {
                Divider()
                HStack(spacing: 12) {
                    if visitCount > 0 {
                        Label("\(visitCount)", systemImage: "camera")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .padding(.trailing, 4)
                    }
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
    let onSave: (String, String, String, [String]) -> Void

    @EnvironmentObject var session: Session
    @State private var name: String
    @State private var tags: [String]
    @State private var wikiURL = ""
    @State private var wikiSummary: WikiSummary?
    @State private var isFetchingWiki = false
    @State private var wikiTask: Task<Void, Never>?
    @State private var nameDebounceTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    init(trip: Trip?, onSave: @escaping (String, String, String, [String]) -> Void) {
        self.trip = trip
        self.onSave = onSave
        _name = State(initialValue: trip?.name ?? "")
        _tags = State(initialValue: trip?.tags ?? [])
        _wikiURL = State(initialValue: trip?.wikiURL ?? "")
        if let desc = trip?.description, !desc.isEmpty {
            _wikiSummary = State(initialValue: WikiSummary(title: trip?.name ?? "", extract: desc, pageURL: nil, thumbnailURL: nil))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Shooting location name", text: $name)
                        .onChange(of: name) { _, newValue in
                            scheduleNameWikiFetch(name: newValue)
                        }
                }
                Section("Tags") {
                    TagChipsEditor(tags: $tags, suggestions: session.allTags)
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
                        onSave(name.trimmingCharacters(in: .whitespaces), wikiSummary?.extract ?? "", wikiURL, tags)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .presentationDetents([.large])
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
