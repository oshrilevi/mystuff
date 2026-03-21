import SwiftUI
import MapKit

struct TripDetailView: View {
    @EnvironmentObject var session: Session
    var trip: Trip

    @State private var editingTrip = false
    @State private var showAddLocation = false
    @State private var editingLocation: TripLocation?
    @State private var editingVisit: TripVisit?
    @State private var focusedLocationId: String? = nil
    @State private var focusedSightingId: String? = nil
    @State private var newLocationCoord: IdentifiableCoordinate? = nil
    @State private var newSightingCoord: IdentifiableCoordinate? = nil
    @State private var headerHovered = false
    @State private var selectedTypes: Set<LocationType> = Set(LocationType.allCases)
    @State private var showSightingsOnMap = true
    @State private var sightingPopup: TripVisit? = nil
    @State private var sightingSortKey: SightingSortKey = .name
    @State private var sightingSortAsc: Bool = true
    @AppStorage("sightingViewMode") private var sightingViewMode: SightingViewMode = .bySpecies
    @State private var selectedSpeciesName: String? = nil

    private var tripsVM: TripsViewModel { session.trips }

    private var currentTrip: Trip {
        tripsVM.trips.first { $0.id == trip.id } ?? trip
    }

    private var orderedLocations: [TripLocation] {
        tripsVM.locations(for: currentTrip)
    }

    private var filteredLocations: [TripLocation] {
        orderedLocations.filter { selectedTypes.contains($0.type) }
    }

    private var visits: [TripVisit] {
        tripsVM.visits(for: currentTrip)
    }

    /// IDs of sighting pins that should be highlighted on the map.
    private var focusedSightingIds: Set<String> {
        if let species = selectedSpeciesName {
            return Set(visits.filter { $0.sightings.contains { $0.name == species } }.map(\.id))
        }
        if let id = focusedSightingId { return [id] }
        return []
    }

    /// Visits that contain the currently selected species (for the aggregated popup).
    private var speciesMatchingVisits: [TripVisit] {
        guard let species = selectedSpeciesName else { return [] }
        return visits.filter { $0.sightings.contains { $0.name == species } }
    }

    var body: some View {
        content
            .navigationTitle(currentTrip.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .onAppear {
                if focusedLocationId == nil {
                    focusedLocationId = orderedLocations.first(where: { $0.latitude != nil })?.id
                }
            }
            .onChange(of: orderedLocations) { _, newLocations in
                // If locations arrive after the view appeared (async load), focus the first one
                if focusedLocationId == nil {
                    focusedLocationId = newLocations.first(where: { $0.latitude != nil })?.id
                }
            }
            .onChange(of: selectedTypes) { _, _ in
                // If the focused location's type was just filtered out, move to the next visible one
                let visibleIds = Set(filteredLocations.map { $0.id })
                if let current = focusedLocationId, !visibleIds.contains(current) {
                    focusedLocationId = filteredLocations.first(where: { $0.latitude != nil })?.id
                }
            }
            .sheet(isPresented: $editingTrip) {
                TripFormSheet(trip: currentTrip) { name, description, wikiURL, tags, lat, lon in
                    var updated = currentTrip
                    updated.name = name
                    updated.description = description
                    updated.wikiURL = wikiURL
                    updated.tags = tags
                    updated.latitude = lat
                    updated.longitude = lon
                    Task { await tripsVM.updateTrip(updated) }
                }
            }
            .sheet(isPresented: $showAddLocation) {
                TripLocationFormSheet(location: nil) { name, description, wikiURL, tags, lat, lon, type, photoIds in
                    Task {
                        await tripsVM.addTripLocation(name: name, description: description, wikiURL: wikiURL, tags: tags, latitude: lat, longitude: lon, type: type, photoIds: photoIds)
                        if let created = tripsVM.tripLocations.last(where: { $0.name == name }) {
                            var updated = currentTrip
                            if !updated.locationIds.contains(created.id) {
                                updated.locationIds.append(created.id)
                            }
                            await tripsVM.updateTrip(updated)
                        }
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .sheet(item: $editingLocation) { loc in
                TripLocationFormSheet(location: loc) { name, description, wikiURL, tags, lat, lon, type, photoIds in
                    var updated = loc
                    updated.name = name
                    updated.description = description
                    updated.wikiURL = wikiURL
                    updated.tags = tags
                    updated.latitude = lat
                    updated.longitude = lon
                    updated.type = type
                    updated.photoIds = photoIds
                    Task { await tripsVM.updateTripLocation(updated) }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .sheet(item: $newLocationCoord) { item in
                TripLocationFormSheet(location: nil, initialCoordinate: item.coordinate) { name, description, wikiURL, tags, lat, lon, type, photoIds in
                    Task {
                        await tripsVM.addTripLocation(name: name, description: description, wikiURL: wikiURL, tags: tags, latitude: lat, longitude: lon, type: type, photoIds: photoIds)
                        if let created = tripsVM.tripLocations.last(where: { $0.name == name }) {
                            var updated = currentTrip
                            if !updated.locationIds.contains(created.id) {
                                updated.locationIds.append(created.id)
                            }
                            await tripsVM.updateTrip(updated)
                        }
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .sheet(item: $editingVisit) { visit in
                TripVisitFormSheet(visit: visit) { sightings, lat, lon, date, timeOfDay, tags, photoIds in
                    var updated = visit
                    updated.sightings = sightings
                    updated.latitude = lat
                    updated.longitude = lon
                    updated.date = date
                    updated.timeOfDay = timeOfDay
                    updated.tags = tags
                    updated.photoIds = photoIds
                    Task { await tripsVM.updateVisit(updated) }
                }
            }
            .sheet(item: $newSightingCoord) { item in
                TripVisitFormSheet(visit: nil, initialCoordinate: item.coordinate) { sightings, lat, lon, date, timeOfDay, tags, photoIds in
                    Task { await tripsVM.addVisit(tripId: currentTrip.id, sightings: sightings, latitude: lat, longitude: lon, date: date, timeOfDay: timeOfDay, tags: tags, photoIds: photoIds) }
                }
            }
    }

    // MARK: - Layout

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            leftPane
                .frame(width: 320)
            Divider()
            ZStack(alignment: .bottom) {
                TripMapView(
                    locations: filteredLocations,
                    sightings: showSightingsOnMap ? visits : [],
                    fallbackCoordinate: currentTrip.latitude.flatMap { lat in currentTrip.longitude.map { lon in CLLocationCoordinate2D(latitude: lat, longitude: lon) } },
                    focusedLocationId: focusedSightingIds.isEmpty ? (focusedLocationId ?? filteredLocations.first(where: { $0.latitude != nil })?.id) : nil,
                    focusedSightingIds: focusedSightingIds,
                    onLocationTapped: { id in
                        focusedLocationId = id
                        focusedSightingId = nil
                        withAnimation { selectedSpeciesName = nil; sightingPopup = nil }
                    },
                    onSightingTapped: { id in
                        focusedSightingId = id
                        focusedLocationId = nil
                        selectedSpeciesName = nil
                        withAnimation { sightingPopup = visits.first(where: { $0.id == id }) }
                    },
                    onMapLongPress: { coord in newLocationCoord = IdentifiableCoordinate(coordinate: coord) },
                    onSightingLongPress: { coord in newSightingCoord = IdentifiableCoordinate(coordinate: coord) }
                )
                if let species = selectedSpeciesName,
                   let group = sortedSpeciesGroups.first(where: { $0.name == species }) {
                    SpeciesAggregatedPopupCard(
                        group: group,
                        matchingVisits: speciesMatchingVisits
                    ) { withAnimation { selectedSpeciesName = nil } }
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let visit = sightingPopup {
                    SightingPopupCard(visit: visit) {
                        withAnimation { sightingPopup = nil }
                    }
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottom) {
                    TripMapView(
                        locations: filteredLocations,
                        sightings: showSightingsOnMap ? visits : [],
                        fallbackCoordinate: currentTrip.latitude.flatMap { lat in currentTrip.longitude.map { lon in CLLocationCoordinate2D(latitude: lat, longitude: lon) } },
                        focusedLocationId: focusedSightingIds.isEmpty ? (focusedLocationId ?? filteredLocations.first(where: { $0.latitude != nil })?.id) : nil,
                        focusedSightingIds: focusedSightingIds,
                        onLocationTapped: { id in
                            focusedLocationId = id
                            focusedSightingId = nil
                            withAnimation { selectedSpeciesName = nil; sightingPopup = nil }
                        },
                        onSightingTapped: { id in
                            focusedSightingId = id
                            focusedLocationId = nil
                            selectedSpeciesName = nil
                            withAnimation { sightingPopup = visits.first(where: { $0.id == id }) }
                        },
                        onMapLongPress: { coord in newLocationCoord = IdentifiableCoordinate(coordinate: coord) },
                        onSightingLongPress: { coord in newSightingCoord = IdentifiableCoordinate(coordinate: coord) }
                    )
                    if let species = selectedSpeciesName,
                       let group = sortedSpeciesGroups.first(where: { $0.name == species }) {
                        SpeciesAggregatedPopupCard(
                            group: group,
                            matchingVisits: speciesMatchingVisits
                        ) { withAnimation { selectedSpeciesName = nil } }
                        .padding(12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let visit = sightingPopup {
                        SightingPopupCard(visit: visit) {
                            withAnimation { sightingPopup = nil }
                        }
                        .padding(12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(height: 280)
                leftPaneContent
                    .padding(.bottom, 24)
            }
        }
        #endif
    }

    private var leftPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                leftPaneContent
                    .padding(.bottom, 24)
            }
            .onChange(of: focusedLocationId) { _, newId in
                if let newId {
                    withAnimation { proxy.scrollTo("loc-\(newId)", anchor: .center) }
                }
            }
        }
    }

    private var leftPaneContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Trip name + edit button (hover to reveal)
            HStack(alignment: .firstTextBaseline) {
                Text(currentTrip.name)
                    .font(.title2.bold())
                Spacer()
                Button { editingTrip = true } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Edit trip")
                #if os(macOS)
                .opacity(headerHovered ? 1 : 0)
                #endif
            }
            .padding(.horizontal)
            .padding(.top, 16)
            #if os(macOS)
            .onHover { headerHovered = $0 }
            #endif

            if !currentTrip.description.isEmpty {
                Text(currentTrip.description)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            typeFilterBar
            locationsSection
            visitsSection
        }
    }

    // MARK: - Type Filter Bar

    private var typeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(LocationType.sorted.enumerated()), id: \.element) { idx, t in
                    TypeFilterButton(
                        locationType: t,
                        count: orderedLocations.filter { $0.type == t }.count,
                        isOn: selectedTypes.contains(t)
                    ) {
                        if selectedTypes.contains(t) { selectedTypes.remove(t) } else { selectedTypes.insert(t) }
                    }
                    Divider().frame(height: 36)
                }
                // Sightings visibility toggle
                Button {
                    showSightingsOnMap.toggle()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: showSightingsOnMap ? "eye.fill" : "eye.slash")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(visits.count)")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(width: 40, height: 36)
                    .foregroundStyle(showSightingsOnMap ? .white : .primary)
                    .background(showSightingsOnMap ? Color.pink : Color.secondary.opacity(0.12))
                }
                .buttonStyle(.plain)
                .help(showSightingsOnMap ? "Hide sightings" : "Show sightings")
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
        }
        .padding(.horizontal)
    }

    // MARK: - Locations Section

    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("אתרים")
                    .font(.title3.bold())
                Spacer()
                Button { showAddLocation = true } label: {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .help("Add location to trip")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if orderedLocations.isEmpty {
                Text("No locations added yet.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(orderedLocations.enumerated()), id: \.element.id) { index, loc in
                    TripLocationRowView(
                        location: loc,
                        index: index,
                        isFocused: focusedLocationId == loc.id,
                        onFocus: {
                            if loc.latitude != nil {
                                focusedLocationId = loc.id
                                focusedSightingId = nil
                            }
                        },
                        onEdit: { editingLocation = loc },
                        onRemove: {
                            var updated = currentTrip
                            updated.locationIds.removeAll { $0 == loc.id }
                            Task { await tripsVM.updateTrip(updated) }
                        }
                    )
                    .id("loc-\(loc.id)")
                }
            }
        }
    }

    // MARK: - Sightings Section

    private var sortedVisits: [TripVisit] {
        visits.sorted {
            let asc: Bool
            switch sightingSortKey {
            case .name:
                let a = $0.sightings.first?.name ?? ""
                let b = $1.sightings.first?.name ?? ""
                asc = a.localizedCompare(b) == .orderedAscending
            case .date:
                asc = $0.date < $1.date
            }
            return sightingSortAsc ? asc : !asc
        }
    }

    private var sortedSpeciesGroups: [SpeciesGroup] {
        // Build a dict keyed by species name
        var dict: [String: (desc: String, imageURL: String, wikiURL: String,
                            obs: [(date: String, timeOfDay: String)])] = [:]
        for visit in visits {
            for s in visit.sightings {
                let key = s.name
                let ob = (date: visit.date, timeOfDay: visit.timeOfDay)
                if dict[key] == nil {
                    dict[key] = (desc: s.wikiDescription, imageURL: s.imageURL,
                                 wikiURL: s.wikiURL, obs: [ob])
                } else {
                    dict[key]!.obs.append(ob)
                }
            }
        }
        let groups = dict.map { (name, val) in
            SpeciesGroup(
                id: name,
                name: name,
                wikiDescription: val.desc,
                imageURL: val.imageURL,
                wikiURL: val.wikiURL,
                observations: val.obs.sorted { $0.date > $1.date }
            )
        }
        return groups.sorted { a, b in
            let asc: Bool
            switch sightingSortKey {
            case .name:
                asc = a.name.localizedCompare(b.name) == .orderedAscending
            case .date:
                asc = (a.observations.first?.date ?? "") < (b.observations.first?.date ?? "")
            }
            return sightingSortAsc ? asc : !asc
        }
    }

    private var visitsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text("תצפיות")
                    .font(.title3.bold())
                Spacer()
                // View mode toggle — centered between title and sort
                SightingViewModeControl(mode: $sightingViewMode)
                    .onChange(of: sightingViewMode) { _, _ in
                        withAnimation { selectedSpeciesName = nil; sightingPopup = nil }
                    }
                Spacer()
                SightingSortControl(sortKey: $sightingSortKey, ascending: $sightingSortAsc)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if visits.isEmpty {
                Text("Right-click on the map to log a sighting.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            } else if sightingViewMode == .byDate {
                ForEach(sortedVisits) { visit in
                    TripVisitRowView(
                        visit: visit,
                        isFocused: focusedSightingId == visit.id,
                        onFocus: {
                            focusedLocationId = nil
                            if visit.latitude != nil { focusedSightingId = visit.id }
                            withAnimation { sightingPopup = visit }
                        },
                        onEdit: { editingVisit = visit },
                        onDelete: { Task { await tripsVM.deleteVisit(id: visit.id) } }
                    )
                }
            } else {
                ForEach(sortedSpeciesGroups) { group in
                    SpeciesGroupRowView(
                        group: group,
                        isFocused: selectedSpeciesName == group.name,
                        onSelect: {
                            focusedLocationId = nil
                            focusedSightingId = nil
                            withAnimation { sightingPopup = nil }
                            withAnimation {
                                selectedSpeciesName = (selectedSpeciesName == group.name) ? nil : group.name
                            }
                        }
                    )
                }
            }
        }
    }

    private func tripTagsView(tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

// MARK: - Type Filter Button

private struct TypeFilterButton: View {
    let locationType: LocationType
    let count: Int
    let isOn: Bool
    let onTap: () -> Void

    private var tooltipLabel: String {
        let base = locationType.rawValue
        let plural = count != 1 ? (base.hasSuffix("s") ? base : base + "s") : base
        return "\(count) \(plural)"
    }

    var body: some View {
        let fg: Color = isOn ? .white : (count == 0 ? Color.secondary.opacity(0.4) : .primary)
        Button(action: onTap) {
            VStack(spacing: 2) {
                Image(systemName: locationType.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(width: 40, height: 36)
            .foregroundStyle(fg)
            .background(isOn ? locationType.color : Color.secondary.opacity(0.12))
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .help(tooltipLabel)
    }
}

// MARK: - Location Row

private struct TripLocationRowView: View {
    let location: TripLocation
    let index: Int
    var isFocused: Bool = false
    let onFocus: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var confirmRemove = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Pin badge — tap focuses on map
            ZStack {
                Circle()
                    .fill(isFocused ? Color.orange : Color.accentColor)
                    .frame(width: 28, height: 28)
                    .shadow(color: isFocused ? Color.orange.opacity(0.5) : .clear, radius: 4)
                Text("\(index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            .onTapGesture { onFocus() }

            // Content — single tap focuses, double tap edits
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(location.name)
                        .font(.headline)
                    HStack(spacing: 3) {
                        Image(systemName: location.type.systemImage)
                            .font(.system(size: 9, weight: .semibold))
                        Text(location.type.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(location.type.color)
                    .background(location.type.color.opacity(0.12), in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !location.description.isEmpty {
                    Text(location.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onEdit() }
            .onTapGesture(count: 1) { onFocus() }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(isFocused ? Color.accentColor.opacity(0.06) : .clear)
        .contextMenu {
            Button("Edit Location") { onEdit() }
            Button("Remove", role: .destructive) { confirmRemove = true }
        }
        .alert("Remove \"\(location.name)\"?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { onRemove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This location will be removed from the trip.")
        }
        Divider()
            .padding(.leading, 52)
    }
}

// MARK: - Visit Row

private struct TripVisitRowView: View {
    let visit: TripVisit
    var isFocused: Bool = false
    let onFocus: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let parseDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var formattedDate: String {
        guard let d = Self.parseDateFormatter.date(from: visit.date) else { return visit.date }
        return Self.displayFormatter.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Date + time of day — always visible
            HStack(spacing: 6) {
                Label(formattedDate, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !visit.timeOfDay.isEmpty {
                    TimeOfDayIcon(rawValue: visit.timeOfDay)
                }
                Spacer()
                if !visit.photoIds.isEmpty {
                    Image(systemName: "photo.on.rectangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Species list
            ForEach(visit.sightings) { s in
                HStack(alignment: .top, spacing: 10) {
                    if let url = URL(string: s.imageURL), !s.imageURL.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Color.secondary.opacity(0.1)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let url = URL(string: s.wikiURL), !s.wikiURL.isEmpty {
                            Link(s.name, destination: url)
                                .font(.subheadline.bold())
                        } else {
                            Text(s.name)
                                .font(.subheadline.bold())
                        }
                        if !s.wikiDescription.isEmpty {
                            Text(s.wikiDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            // Tags
            if !visit.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(visit.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(isFocused ? Color.pink.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit() }
        .onTapGesture(count: 1) { onFocus() }
        .contextMenu {
            Button("Edit Sighting") { onEdit() }
            Button("Delete", role: .destructive) { confirmDelete = true }
        }
        .alert("Delete this sighting?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let names = visit.sightings.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
            Text(names.isEmpty ? "This sighting will be permanently deleted." : "\"\(names)\" will be permanently deleted.")
        }
        Divider()
            .padding(.leading)
    }
}

// MARK: - Sighting Popup Card

private struct SightingPopupCard: View {
    let visit: TripVisit
    let onDismiss: () -> Void

    private static let parseDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    private var formattedDate: String {
        guard let d = Self.parseDateFormatter.date(from: visit.date) else { return visit.date }
        return Self.displayFormatter.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Label(formattedDate, systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                if !visit.timeOfDay.isEmpty {
                    TimeOfDayIcon(rawValue: visit.timeOfDay)
                }
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Observations
            ForEach(visit.sightings) { s in
                HStack(alignment: .top, spacing: 8) {
                    if let url = URL(string: s.imageURL), !s.imageURL.isEmpty {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                            else { Color.secondary.opacity(0.1) }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let url = URL(string: s.wikiURL), !s.wikiURL.isEmpty {
                            Link(s.name, destination: url)
                                .font(.subheadline.bold())
                        } else {
                            Text(s.name).font(.subheadline.bold())
                        }
                        if !s.wikiDescription.isEmpty {
                            Text(s.wikiDescription).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
            }

            // Linked photos
            if !visit.photoIds.isEmpty {
                Divider()
                Text("תמונות")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visit.photoIds, id: \.self) { identifier in
                            PHAssetThumbnail(identifier: identifier, size: 80)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .frame(maxWidth: 400)
    }
}

// MARK: - Sighting Sort

// MARK: - Sighting view mode

private enum SightingViewMode: String {
    case byDate, bySpecies
}

private struct SightingViewModeControl: View {
    @Binding var mode: SightingViewMode

    var body: some View {
        HStack(spacing: 1) {
            modeButton(icon: "calendar", target: .byDate, tooltip: "לפי תאריך")
            modeButton(icon: "bird", target: .bySpecies, tooltip: "לפי מין")
        }
        .padding(2)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
    }

    private func modeButton(icon: String, target: SightingViewMode, tooltip: String) -> some View {
        let active = mode == target
        return Button { mode = target } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 22)
                .background(active ? Color.accentColor.opacity(0.2) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

// MARK: - Species group model

private struct SpeciesGroup: Identifiable {
    let id: String
    let name: String
    let wikiDescription: String
    let imageURL: String
    let wikiURL: String
    let observations: [(date: String, timeOfDay: String)]
}

// MARK: - Species group row

private struct SpeciesGroupRowView: View {
    let group: SpeciesGroup
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil

    @State private var obsExpanded = false

    private static let collapsedLimit = 4

    private static let parseFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let displayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    private func fmt(_ s: String) -> String {
        guard let d = Self.parseFmt.date(from: s) else { return s }
        return Self.displayFmt.string(from: d)
    }

    private var visibleObs: [(offset: Int, element: (date: String, timeOfDay: String))] {
        let all = Array(group.observations.enumerated())
        return obsExpanded ? all : Array(all.prefix(Self.collapsedLimit))
    }

    private var hasMore: Bool { group.observations.count > Self.collapsedLimit }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Species header row
            HStack(alignment: .top, spacing: 10) {
                if let url = URL(string: group.imageURL), !group.imageURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                        default: Color.secondary.opacity(0.1)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(group.name).font(.subheadline.bold())
                        Text("×\(group.observations.count)")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    if !group.wikiDescription.isEmpty {
                        Text(group.wikiDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !group.wikiURL.isEmpty, let url = URL(string: group.wikiURL) {
                        Link(destination: url) {
                            Label("Wikipedia", systemImage: "arrow.up.right.square")
                                .font(.caption2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Observation dates — 2-column grid
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                alignment: .leading,
                spacing: 4
            ) {
                ForEach(visibleObs, id: \.offset) { item in
                    let obs = item.element
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(fmt(obs.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !obs.timeOfDay.isEmpty {
                            TimeOfDayIcon(rawValue: obs.timeOfDay, fontSize: .caption2)
                        }
                    }
                }
            }

            // Expand / collapse
            if hasMore {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { obsExpanded.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: obsExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                        Text(obsExpanded
                             ? "הצג פחות"
                             : "הצג עוד \(group.observations.count - Self.collapsedLimit)")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(isFocused ? Color.pink.opacity(0.07) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
        Divider().padding(.leading)
    }
}

// MARK: - Species aggregated popup

private struct SpeciesAggregatedPopupCard: View {
    let group: SpeciesGroup
    let matchingVisits: [TripVisit]
    let onDismiss: () -> Void

    @State private var obsExpanded = false
    private static let collapsedLimit = 4

    private static let parseFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let displayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    private func fmt(_ s: String) -> String {
        guard let d = Self.parseFmt.date(from: s) else { return s }
        return Self.displayFmt.string(from: d)
    }

    private var allPhotoIds: [String] {
        var seen = Set<String>()
        return matchingVisits.flatMap(\.photoIds).filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(alignment: .top, spacing: 10) {
                    if let url = URL(string: group.imageURL), !group.imageURL.isEmpty {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                            else { Color.secondary.opacity(0.1) }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if !group.wikiURL.isEmpty, let url = URL(string: group.wikiURL) {
                            Link(group.name, destination: url).font(.headline.bold())
                        } else {
                            Text(group.name).font(.headline.bold())
                        }
                        if !group.wikiDescription.isEmpty {
                            Text(group.wikiDescription)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Observations list
            Text("תצפיות")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                alignment: .leading,
                spacing: 4
            ) {
                let visible = obsExpanded
                    ? Array(group.observations.enumerated())
                    : Array(group.observations.prefix(Self.collapsedLimit).enumerated())
                ForEach(visible, id: \.offset) { _, obs in
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.caption2).foregroundStyle(.tertiary)
                        Text(fmt(obs.date)).font(.caption).foregroundStyle(.secondary)
                        if !obs.timeOfDay.isEmpty {
                            TimeOfDayIcon(rawValue: obs.timeOfDay, fontSize: .caption2)
                        }
                    }
                }
            }
            if group.observations.count > Self.collapsedLimit {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { obsExpanded.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: obsExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                        Text(obsExpanded
                             ? "הצג פחות"
                             : "הצג עוד \(group.observations.count - Self.collapsedLimit)")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            // Photos
            if !allPhotoIds.isEmpty {
                Divider()
                Text("תמונות")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allPhotoIds, id: \.self) { identifier in
                            PHAssetThumbnail(identifier: identifier, size: 80)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .frame(maxWidth: 420)
    }
}

// MARK: - Time-of-day icon

/// Shows the SF Symbol that matches the time-of-day slot.
/// Hovering reveals the Hebrew label as a tooltip.
private struct TimeOfDayIcon: View {
    let rawValue: String
    var fontSize: Font = .caption

    private var tod: TimeOfDay? { TimeOfDay(rawValue: rawValue) }

    var body: some View {
        Image(systemName: tod?.systemImage ?? "clock")
            .font(fontSize)
            .foregroundStyle(.secondary)
            .help(tod?.hebrewLabel ?? rawValue)
    }
}

// MARK: - Sort key

private enum SightingSortKey: String, CaseIterable {
    case name = "שם"
    case date = "תאריך"
}

private struct SightingSortControl: View {
    @Binding var sortKey: SightingSortKey
    @Binding var ascending: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SightingSortKey.allCases, id: \.self) { key in
                Button {
                    if sortKey == key {
                        ascending.toggle()
                    } else {
                        sortKey = key
                        ascending = true
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(key.rawValue)
                        if sortKey == key {
                            Image(systemName: ascending ? "arrow.up" : "arrow.down")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(sortKey == key ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Helpers

struct IdentifiableCoordinate: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
