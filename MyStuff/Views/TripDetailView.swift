import SwiftUI
import MapKit

struct TripDetailView: View {
    @EnvironmentObject var session: Session
    var trip: Trip

    @State private var editingTrip = false
    @State private var showAddLocation = false
    @State private var showAddVisit = false
    @State private var editingLocation: TripLocation?
    @State private var editingVisit: TripVisit?
    @State private var focusedLocationId: String? = nil
    @State private var newLocationCoord: IdentifiableCoordinate? = nil
    @State private var headerHovered = false

    private var tripsVM: TripsViewModel { session.trips }

    private var currentTrip: Trip {
        tripsVM.trips.first { $0.id == trip.id } ?? trip
    }

    private var orderedLocations: [TripLocation] {
        tripsVM.locations(for: currentTrip)
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
            .sheet(isPresented: $editingTrip) {
                TripFormSheet(trip: currentTrip) { name, description, wikiURL, tags in
                    var updated = currentTrip
                    updated.name = name
                    updated.description = description
                    updated.wikiURL = wikiURL
                    updated.tags = tags
                    Task { await tripsVM.updateTrip(updated) }
                }
            }
            .sheet(isPresented: $showAddLocation) {
                TripLocationFormSheet(location: nil) { name, description, wikiURL, tags, lat, lon in
                    Task {
                        await tripsVM.addTripLocation(name: name, description: description, wikiURL: wikiURL, tags: tags, latitude: lat, longitude: lon)
                        if let created = tripsVM.tripLocations.last(where: { $0.name == name }) {
                            var updated = currentTrip
                            if !updated.locationIds.contains(created.id) {
                                updated.locationIds.append(created.id)
                            }
                            await tripsVM.updateTrip(updated)
                        }
                    }
                }
                .environment(\.layoutDirection, .rightToLeft)
                .multilineTextAlignment(.leading)
            }
            .sheet(isPresented: $showAddVisit) {
                TripVisitFormSheet(visit: nil, locations: orderedLocations) { locationId, date, summary, tags in
                    Task { await tripsVM.addVisit(tripId: currentTrip.id, locationId: locationId, date: date, summary: summary, tags: tags) }
                }
            }
            .sheet(item: $editingLocation) { loc in
                TripLocationFormSheet(location: loc) { name, description, wikiURL, tags, lat, lon in
                    var updated = loc
                    updated.name = name
                    updated.description = description
                    updated.wikiURL = wikiURL
                    updated.tags = tags
                    updated.latitude = lat
                    updated.longitude = lon
                    Task { await tripsVM.updateTripLocation(updated) }
                }
            }
            .sheet(item: $newLocationCoord) { item in
                TripLocationFormSheet(location: nil, initialCoordinate: item.coordinate) { name, description, wikiURL, tags, lat, lon in
                    Task {
                        await tripsVM.addTripLocation(name: name, description: description, wikiURL: wikiURL, tags: tags, latitude: lat, longitude: lon)
                        if let created = tripsVM.tripLocations.last(where: { $0.name == name }) {
                            var updated = currentTrip
                            if !updated.locationIds.contains(created.id) {
                                updated.locationIds.append(created.id)
                            }
                            await tripsVM.updateTrip(updated)
                        }
                    }
                }
            }
            .sheet(item: $editingVisit) { visit in
                TripVisitFormSheet(visit: visit, locations: orderedLocations) { locationId, date, summary, tags in
                    var updated = visit
                    updated.locationId = locationId
                    updated.date = date
                    updated.summary = summary
                    updated.tags = tags
                    Task { await tripsVM.updateVisit(updated) }
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
            TripMapView(
                locations: orderedLocations,
                focusedLocationId: focusedLocationId ?? orderedLocations.first(where: { $0.latitude != nil })?.id,
                onLocationTapped: { id in focusedLocationId = id },
                onMapLongPress: { coord in newLocationCoord = IdentifiableCoordinate(coordinate: coord) }
            )
        }
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TripMapView(
                    locations: orderedLocations,
                    focusedLocationId: focusedLocationId ?? orderedLocations.first(where: { $0.latitude != nil })?.id,
                    onLocationTapped: { id in focusedLocationId = id },
                    onMapLongPress: { coord in newLocationCoord = IdentifiableCoordinate(coordinate: coord) }
                )
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
            locationsSection
            visitsSection
        }
    }

    // MARK: - Locations Section

    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Locations")
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
            HStack {
                Text("Sightings")
                    .font(.title3.bold())
                Spacer()
                Button { showAddVisit = true } label: {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .help("Log a sighting")
                .disabled(orderedLocations.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if visits.isEmpty {
                Text("No sightings logged yet.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            } else {
                ForEach(visits) { visit in
                    TripVisitRowView(
                        visit: visit,
                        location: tripsVM.tripLocations.first { $0.id == visit.locationId },
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

// MARK: - Location Row

private struct TripLocationRowView: View {
    let location: TripLocation
    let index: Int
    var isFocused: Bool = false
    let onFocus: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

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
                Text(location.name)
                    .font(.headline)
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
            Button("Remove", role: .destructive) { onRemove() }
        }
        Divider()
            .padding(.leading, 52)
    }
}

// MARK: - Visit Row

private struct TripVisitRowView: View {
    let visit: TripVisit
    let location: TripLocation?
    let onEdit: () -> Void
    let onDelete: () -> Void

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let parseFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var formattedDate: String {
        guard let d = Self.parseFormatter.date(from: visit.date) else { return visit.date }
        return Self.displayFormatter.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate)
                        .font(.subheadline.bold())
                    if let loc = location {
                        Label(loc.name, systemImage: "mappin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Edit") { onEdit() }
                    Button("Delete", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            if !visit.summary.isEmpty {
                Text(visit.summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
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
        Divider()
            .padding(.leading)
    }
}

// MARK: - Helpers

struct IdentifiableCoordinate: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
