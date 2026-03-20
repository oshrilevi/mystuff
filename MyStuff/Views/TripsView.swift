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
            .navigationDestination(item: $selectedTrip) { trip in
                TripDetailView(trip: trip)
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
            LazyVGrid(columns: Self.gridColumns, spacing: 16) {
                ForEach(tripsVM.filteredTrips) { trip in
                    TripCardView(
                        trip: trip,
                        locations: tripsVM.locations(for: trip),
                        visitCount: tripsVM.visits(for: trip).count
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { selectedTrip = trip }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await tripsVM.deleteTrips([trip]) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

private struct TripCardView: View {
    let trip: Trip
    let locations: [TripLocation]
    let visitCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(trip.name)
                    .font(.headline)
                    .lineLimit(2)

                if !trip.description.isEmpty {
                    Text(trip.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Footer stats
            HStack(spacing: 12) {
                Label("\(locations.count)", systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if visitCount > 0 {
                    Label("\(visitCount)", systemImage: "camera")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 0.5)
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
            _wikiSummary = State(initialValue: WikiSummary(title: trip?.name ?? "", extract: desc, pageURL: nil))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Trip name", text: $name)
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
                        onSave(name.trimmingCharacters(in: .whitespaces), wikiSummary?.extract ?? "", wikiURL, tags)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
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
