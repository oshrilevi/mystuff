import SwiftUI
import MapKit

// MARK: - Navigation item

private struct TripNavItem: Identifiable, Hashable {
    let id = UUID()
    let trip: Trip
    let focusedLocationId: String?
    let selectedSpeciesName: String?

    init(trip: Trip, focusedLocationId: String? = nil, selectedSpeciesName: String? = nil) {
        self.trip = trip
        self.focusedLocationId = focusedLocationId
        self.selectedSpeciesName = selectedSpeciesName
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Main view

struct TripsView: View {
    @EnvironmentObject var session: Session
    @State private var showAddTrip = false
    @State private var editingTrip: Trip?
    @State private var tripPendingDelete: Trip?
    @State private var deletingTripId: String?
    @State private var selectedNavItem: TripNavItem?
    @State private var speciesTripPickerName: String? = nil
    @State private var tripsFilter: String = ""
    @State private var locationsFilter: String = ""
    @State private var speciesFilter: String = ""
    @AppStorage("lastSelectedTripId") private var lastSelectedTripId: String = ""

    private var tripsVM: TripsViewModel { session.trips }

    var body: some View {
        NavigationStack {
            Group {
                if tripsVM.isLoading && tripsVM.trips.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tripsVM.trips.isEmpty {
                    ContentUnavailableView(
                        "No Field Journal Entries Yet",
                        systemImage: "map",
                        description: Text("Tap + to add your first location.")
                    )
                } else {
                    #if os(macOS)
                    threePaneLayout
                    #else
                    tripGrid
                    #endif
                }
            }
            .navigationTitle("Field Journal")
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
            .confirmationDialog(
                speciesTripPickerName.map { "בחר אתר עבור \($0)" } ?? "",
                isPresented: Binding(
                    get: { speciesTripPickerName != nil },
                    set: { if !$0 { speciesTripPickerName = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let name = speciesTripPickerName {
                    let matchingTrips = tripsVM.filteredTrips.filter { trip in
                        tripsVM.visits(for: trip).contains(where: { $0.sightings.contains(where: { $0.name == name }) })
                    }
                    ForEach(matchingTrips) { trip in
                        Button(trip.name) {
                            selectedNavItem = TripNavItem(trip: trip, selectedSpeciesName: name)
                            speciesTripPickerName = nil
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedNavItem) { item in
                TripDetailView(
                    trip: item.trip,
                    initialFocusedLocationId: item.focusedLocationId,
                    initialSelectedSpeciesName: item.selectedSpeciesName
                )
                .environment(\.layoutDirection, .rightToLeft)
                .multilineTextAlignment(.leading)
            }
            .onChange(of: selectedNavItem) { _, item in
                lastSelectedTripId = item?.trip.id ?? ""
            }
            .task {
                await tripsVM.load()
                if selectedNavItem == nil, !lastSelectedTripId.isEmpty {
                    if let trip = tripsVM.trips.first(where: { $0.id == lastSelectedTripId }) {
                        selectedNavItem = TripNavItem(trip: trip)
                    }
                }
            }
            .refreshable { await tripsVM.load() }
        }
    }

    // MARK: - iOS Grid

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
                        .onTapGesture {
                            if deletingTripId != trip.id {
                                selectedNavItem = TripNavItem(trip: trip)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - macOS Three-Pane Layout

    #if os(macOS)
    private var threePaneLayout: some View {
        HSplitView {
            allSpeciesPane
                .frame(minWidth: 200, idealWidth: 280)
            allLocationsPane
                .frame(minWidth: 180, idealWidth: 250, maxWidth: 360)
            tripsListPane
                .frame(minWidth: 180, idealWidth: 230, maxWidth: 320)
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    // Right pane (RTL): shooting locations (trips)
    private var tripsListPane: some View {
        VStack(spacing: 0) {
            paneHeader("אתרי צילום", count: filteredTripsForPane.count)
            paneFilterField($tripsFilter, placeholder: "חיפוש לפי שם או תיאור")
            if filteredTripsForPane.isEmpty {
                emptyPane(label: "אין תוצאות")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredTripsForPane) { trip in
                            TripListRow(
                                trip: trip,
                                locationCount: tripsVM.locations(for: trip).count,
                                visitCount: tripsVM.visits(for: trip).count,
                                isSelected: selectedNavItem?.trip.id == trip.id,
                                isDeleting: deletingTripId == trip.id,
                                onEdit: { editingTrip = trip },
                                onDelete: { tripPendingDelete = trip }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if deletingTripId != trip.id {
                                    selectedNavItem = TripNavItem(trip: trip)
                                }
                            }
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // Center pane: all TripLocations across filtered trips
    private var allLocationsPane: some View {
        VStack(spacing: 0) {
            paneHeader("מיקומים", count: filteredLocationsForPane.count)
            paneFilterField($locationsFilter, placeholder: "חיפוש לפי שם או תיאור")
            if filteredLocationsForPane.isEmpty {
                emptyPane(label: "אין אתרים")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredLocationsForPane, id: \.location.id) { item in
                            GlobalLocationRow(location: item.location, tripName: item.tripName)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let trip = tripsVM.trips.first(where: { $0.locationIds.contains(item.location.id) }) {
                                        selectedNavItem = TripNavItem(trip: trip, focusedLocationId: item.location.id)
                                    }
                                }
                            Divider().padding(.trailing, 52)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // Left pane (RTL): aggregated species observations across all filtered trips
    private var allSpeciesPane: some View {
        VStack(spacing: 0) {
            paneHeader("תצפיות", count: filteredSpeciesForPane.count)
            paneFilterField($speciesFilter, placeholder: "חיפוש לפי שם מין או תיאור", autoFocus: true)
            if filteredSpeciesForPane.isEmpty {
                emptyPane(label: "אין תצפיות")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSpeciesForPane, id: \.name) { species in
                            GlobalSpeciesRow(
                                name: species.name,
                                imageURL: species.imageURL,
                                wikiURL: species.wikiURL,
                                wikiDescription: species.desc,
                                totalCount: species.count,
                                tripCount: species.matchingTripIds.count
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if species.matchingTripIds.count > 1 {
                                    speciesTripPickerName = species.name
                                } else if let tripId = species.matchingTripIds.first,
                                          let trip = tripsVM.trips.first(where: { $0.id == tripId }) {
                                    selectedNavItem = TripNavItem(trip: trip, selectedSpeciesName: species.name)
                                }
                            }
                            .contextMenu {
                                ForEach(species.matchingTripIds, id: \.self) { tripId in
                                    if let trip = tripsVM.trips.first(where: { $0.id == tripId }) {
                                        Button(trip.name) {
                                            selectedNavItem = TripNavItem(trip: trip, selectedSpeciesName: species.name)
                                        }
                                    }
                                }
                            }
                            Divider().padding(.trailing, 52)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Pane data

    private var filteredTripsForPane: [Trip] {
        guard !tripsFilter.isEmpty else { return tripsVM.filteredTrips }
        let q = tripsFilter.lowercased()
        return tripsVM.filteredTrips.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    private var filteredLocationsForPane: [(location: TripLocation, tripName: String)] {
        guard !locationsFilter.isEmpty else { return allFilteredLocations }
        let q = locationsFilter.lowercased()
        return allFilteredLocations.filter {
            $0.location.name.lowercased().contains(q) || $0.location.description.lowercased().contains(q)
        }
    }

    private var filteredSpeciesForPane: [SpeciesAgg] {
        guard !speciesFilter.isEmpty else { return allSpeciesGroups }
        let q = speciesFilter.lowercased()
        return allSpeciesGroups.filter {
            $0.name.lowercased().contains(q) || $0.desc.lowercased().contains(q)
        }
    }

    private var allFilteredLocations: [(location: TripLocation, tripName: String)] {
        var seen = Set<String>()
        var result: [(TripLocation, String)] = []
        for trip in tripsVM.filteredTrips {
            for locId in trip.locationIds {
                guard let loc = tripsVM.tripLocations.first(where: { $0.id == locId }),
                      !seen.contains(locId) else { continue }
                seen.insert(locId)
                result.append((loc, trip.name))
            }
        }
        return result.sorted { $0.0.name.localizedCompare($1.0.name) == .orderedAscending }
    }

    private struct SpeciesAgg {
        let name: String
        let imageURL: String
        let wikiURL: String
        let desc: String
        let count: Int
        let matchingTripIds: [String]
    }

    private var allSpeciesGroups: [SpeciesAgg] {
        var dict: [String: (imageURL: String, wikiURL: String, desc: String, count: Int, tripIds: [String])] = [:]
        for trip in tripsVM.filteredTrips {
            for visit in tripsVM.visits(for: trip) {
                for s in visit.sightings where !s.name.isEmpty {
                    if dict[s.name] == nil {
                        dict[s.name] = (s.imageURL, s.wikiURL, s.wikiDescription, 1, [trip.id])
                    } else {
                        dict[s.name]!.count += 1
                        if !dict[s.name]!.tripIds.contains(trip.id) {
                            dict[s.name]!.tripIds.append(trip.id)
                        }
                    }
                }
            }
        }
        return dict.map { SpeciesAgg(name: $0.key, imageURL: $0.value.imageURL, wikiURL: $0.value.wikiURL, desc: $0.value.desc, count: $0.value.count, matchingTripIds: $0.value.tripIds) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // MARK: - Pane helpers

    @ViewBuilder
    private func paneHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        Divider()
    }

    @ViewBuilder
    private func paneFilterField(_ text: Binding<String>, placeholder: String, autoFocus: Bool = false) -> some View {
        HStack(spacing: 6) {
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            RTLFilterTextField(text: text, placeholder: placeholder, autoFocus: autoFocus)
                .frame(height: 20)
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        Divider()
    }

    private func emptyPane(label: String) -> some View {
        Text(label)
            .foregroundStyle(.tertiary)
            .font(.subheadline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }
    #endif
}

// MARK: - macOS pane row views

#if os(macOS)
private struct RTLFilterTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var autoFocus: Bool = false

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.baseWritingDirection = .rightToLeft
        field.alignment = .right
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        nsView.placeholderString = placeholder
        if autoFocus && !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var didFocus = false
        init(text: Binding<String>) { _text = text }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }
    }
}

private struct TripListRow: View {
    let trip: Trip
    let locationCount: Int
    let visitCount: Int
    let isSelected: Bool
    let isDeleting: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.name)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !trip.description.isEmpty {
                    Text(trip.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    if locationCount > 0 {
                        Label("\(locationCount)", systemImage: "mappin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if visitCount > 0 {
                        Label("\(visitCount)", systemImage: "eye")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if isDeleting {
                ProgressView().scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
        .opacity(isDeleting ? 0.5 : 1)
        .environment(\.layoutDirection, .rightToLeft)
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button { onEdit() } label: { Label("ערוך", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("מחק", systemImage: "trash") }
        }
    }
}

private struct GlobalLocationRow: View {
    let location: TripLocation
    let tripName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(location.type.color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: location.type.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(location.type.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(location.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(tripName)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                if !location.description.isEmpty {
                    Text(location.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct GlobalSpeciesRow: View {
    let name: String
    let imageURL: String
    let wikiURL: String
    let wikiDescription: String
    let totalCount: Int
    var tripCount: Int = 1

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let url = URL(string: imageURL), !imageURL.isEmpty {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.secondary.opacity(0.1)
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.subheadline.bold())
                    Text("×\(totalCount)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                    if tripCount > 1 {
                        Image(systemName: "camera.on.rectangle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("\(tripCount) אתרי צילום")
                    }
                }
                if !wikiDescription.isEmpty {
                    Text(wikiDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
#endif

// MARK: - Trip card (iOS grid)

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

// MARK: - Trip form

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
            .navigationTitle(trip == nil ? "New Journal Entry" : "Edit Journal Entry")
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
