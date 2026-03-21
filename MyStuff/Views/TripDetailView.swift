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
    @State private var expandedSightingIds: Set<String> = []
    @State private var newLocationCoord: IdentifiableCoordinate? = nil
    @State private var newSightingCoord: IdentifiableCoordinate? = nil
    @State private var headerHovered = false
    @State private var selectedTypes: Set<LocationType> = Set(LocationType.allCases)
    @State private var showSightingsOnMap = true
    @State private var sightingPopup: TripVisit? = nil

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
                    focusedLocationId: focusedSightingId == nil ? (focusedLocationId ?? filteredLocations.first(where: { $0.latitude != nil })?.id) : focusedLocationId,
                    focusedSightingId: focusedSightingId,
                    onLocationTapped: { id in focusedLocationId = id; focusedSightingId = nil },
                    onSightingTapped: { id in
                        focusedSightingId = id
                        focusedLocationId = nil
                        withAnimation { sightingPopup = visits.first(where: { $0.id == id }) }
                    },
                    onMapLongPress: { coord in newLocationCoord = IdentifiableCoordinate(coordinate: coord) },
                    onSightingLongPress: { coord in newSightingCoord = IdentifiableCoordinate(coordinate: coord) }
                )
                if let visit = sightingPopup {
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
                        focusedLocationId: focusedSightingId == nil ? (focusedLocationId ?? filteredLocations.first(where: { $0.latitude != nil })?.id) : focusedLocationId,
                        focusedSightingId: focusedSightingId,
                        onLocationTapped: { id in focusedLocationId = id; focusedSightingId = nil },
                        onSightingTapped: { id in
                            focusedSightingId = id
                            focusedLocationId = nil
                            withAnimation { sightingPopup = visits.first(where: { $0.id == id }) }
                        },
                        onMapLongPress: { coord in newLocationCoord = IdentifiableCoordinate(coordinate: coord) },
                        onSightingLongPress: { coord in newSightingCoord = IdentifiableCoordinate(coordinate: coord) }
                    )
                    if let visit = sightingPopup {
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

    private var visitsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("תצפיות")
                .font(.title3.bold())
                .padding(.horizontal)
                .padding(.bottom, 8)

            if visits.isEmpty {
                Text("Right-click on the map to log a sighting.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            } else {
                ForEach(visits) { visit in
                    TripVisitRowView(
                        visit: visit,
                        isExpanded: expandedSightingIds.contains(visit.id),
                        isFocused: focusedSightingId == visit.id,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedSightingIds.contains(visit.id) {
                                    expandedSightingIds.remove(visit.id)
                                } else {
                                    expandedSightingIds.insert(visit.id)
                                }
                            }
                        },
                        onFocus: {
                            focusedLocationId = nil
                            if visit.latitude != nil { focusedSightingId = visit.id }
                            withAnimation { sightingPopup = visit }
                        },
                        onEdit: { editingVisit = visit },
                        onDelete: { Task { await tripsVM.deleteVisit(id: visit.id) } }
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
    var isExpanded: Bool = false
    var isFocused: Bool = false
    let onToggleExpand: () -> Void
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
                    Label(TimeOfDay(rawValue: visit.timeOfDay)?.hebrewLabel ?? visit.timeOfDay, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !visit.photoIds.isEmpty {
                    Image(systemName: "photo.on.rectangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Species list
            if isExpanded {
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
                            Text(s.name)
                                .font(.subheadline.bold())
                            if !s.wikiDescription.isEmpty {
                                Text(s.wikiDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            } else {
                let names = visit.sightings.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
                if !names.isEmpty {
                    Text(names)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }
            }

            // Tags — only when expanded
            if isExpanded && !visit.tags.isEmpty {
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
        .onTapGesture(count: 1) {
            onToggleExpand()
            onFocus()
        }
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
                    Label(TimeOfDay(rawValue: visit.timeOfDay)?.hebrewLabel ?? visit.timeOfDay, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
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

// MARK: - Helpers

struct IdentifiableCoordinate: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
