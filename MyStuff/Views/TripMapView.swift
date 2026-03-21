import SwiftUI
import MapKit

// MARK: - Map Style

enum TripMapStyle: String, CaseIterable, Identifiable {
    case standard
    case topo
    case satellite
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard:  return "Roads"
        case .topo:      return "Terrain"
        case .satellite: return "Satellite"
        case .hybrid:    return "Hybrid"
        }
    }

    var systemImage: String {
        switch self {
        case .standard:  return "road.lanes"
        case .topo:      return "mountain.2"
        case .satellite: return "globe"
        case .hybrid:    return "map"
        }
    }

    @available(iOS 17.0, macOS 14.0, *)
    var mapStyle: MapStyle {
        switch self {
        case .standard:  return .standard(elevation: .flat)
        case .topo:      return .standard(elevation: .realistic)
        case .satellite: return .imagery(elevation: .realistic)
        case .hybrid:    return .hybrid(elevation: .realistic)
        }
    }

    var legacyMapType: MKMapType {
        switch self {
        case .standard:  return .standard
        case .topo:      return .standard
        case .satellite: return .satellite
        case .hybrid:    return .hybrid
        }
    }
}

// MARK: - TripMapView

struct TripMapView: View {
    let locations: [TripLocation]
    var sightings: [TripVisit] = []
    var fallbackCoordinate: CLLocationCoordinate2D? = nil
    var focusedLocationId: String? = nil
    var focusedSightingIds: Set<String> = []
    var onLocationTapped: ((String) -> Void)? = nil
    var onSightingTapped: ((String) -> Void)? = nil
    var onMapLongPress: ((CLLocationCoordinate2D) -> Void)? = nil
    var onSightingLongPress: ((CLLocationCoordinate2D) -> Void)? = nil

    @AppStorage("tripMapStyle")    private var mapStyle: TripMapStyle = .standard
    @AppStorage("inatTaxonFilter") private var inatTaxonFilter: InatTaxonFilter = .birds
    @AppStorage("showInatOverlay") private var showInatOverlay = true

    private var coordinatedSightings: [(sighting: TripVisit, coord: CLLocationCoordinate2D)] {
        sightings.compactMap { s in
            guard let lat = s.latitude, let lon = s.longitude else { return nil }
            return (s, CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    private var coordinatedLocations: [(index: Int, location: TripLocation, coord: CLLocationCoordinate2D)] {
        locations.enumerated().compactMap { idx, loc in
            guard let lat = loc.latitude, let lon = loc.longitude else { return nil }
            return (idx, loc, CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    private var boundingRegion: MKCoordinateRegion {
        let coords = coordinatedLocations.map { $0.coord }
        guard !coords.isEmpty else {
            if let fallback = fallbackCoordinate {
                return MKCoordinateRegion(
                    center: fallback,
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                )
            }
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 30, longitude: 15),
                span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
            )
        }
        if coords.count == 1 {
            return MKCoordinateRegion(
                center: coords[0],
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        let minLat = coords.map { $0.latitude }.min()!
        let maxLat = coords.map { $0.latitude }.max()!
        let minLon = coords.map { $0.longitude }.min()!
        let maxLon = coords.map { $0.longitude }.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.5 + 0.05, longitudeDelta: (maxLon - minLon) * 1.5 + 0.05)
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        ZStack {
            if #available(iOS 17.0, macOS 14.0, *) {
                ModernTripMapView(
                    coordinatedLocations: coordinatedLocations,
                    coordinatedSightings: coordinatedSightings,
                    initialRegion: boundingRegion,
                    focusedLocationId: focusedLocationId,
                    focusedSightingIds: focusedSightingIds,
                    mapStyle: mapStyle,
                    showInatOverlay: showInatOverlay,
                    inatTaxonFilter: inatTaxonFilter,
                    onLocationTapped: onLocationTapped,
                    onSightingTapped: onSightingTapped,
                    onMapLongPress: onMapLongPress,
                    onSightingLongPress: onSightingLongPress
                )
                .id(coordinatedLocations.map { $0.location.id }.joined(separator: ","))
            } else {
                TripMapLegacyView(
                    region: boundingRegion,
                    coordinatedLocations: coordinatedLocations,
                    focusedLocationId: focusedLocationId,
                    mapStyle: mapStyle,
                    onLocationTapped: onLocationTapped
                )
            }
        }
        .overlay(alignment: .topLeading) {
            if #available(iOS 17.0, macOS 14.0, *) {
                InatOverlayButton(showOverlay: $showInatOverlay, taxonFilter: $inatTaxonFilter)
                    .padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
            MapStylePicker(selected: $mapStyle)
                .padding(10)
        }
    }
}

// MARK: - Style Picker

private struct MapStylePicker: View {
    @Binding var selected: TripMapStyle

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TripMapStyle.allCases) { style in
                let isSelected = style == selected
                Button { selected = style } label: {
                    VStack(spacing: 3) {
                        Image(systemName: style.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        Text(style.label)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(isSelected ? .white : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.accentColor : Color.clear)
                }
                .buttonStyle(.plain)
                .help(style.label)
            }
        }
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}

// MARK: - iNaturalist Overlay Toggle

@available(iOS 17.0, macOS 14.0, *)
private struct InatOverlayButton: View {
    @Binding var showOverlay: Bool
    @Binding var taxonFilter: InatTaxonFilter

    var body: some View {
        Menu {
            Toggle(isOn: $showOverlay) {
                Label("iNaturalist Overlay", systemImage: "binoculars.fill")
            }
            if showOverlay {
                Divider()
                Picker("Filter", selection: $taxonFilter) {
                    ForEach(InatTaxonFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "binoculars.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Wildlife")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(showOverlay ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(showOverlay ? Color.teal : Color.clear)
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .fixedSize()
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}

// MARK: - Pin View (extracted to avoid compiler type-check timeout)

private struct TripMapPin: View {
    let locationType: LocationType
    let isFocused: Bool

    var body: some View {
        let pinColor = locationType.color
        ZStack {
            // Outer ring — visible only when focused
            if isFocused {
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: 38, height: 38)
                    .shadow(color: pinColor.opacity(0.5), radius: 6)
            }
            Circle()
                .fill(pinColor.opacity(isFocused ? 1.0 : 0.85))
                .frame(width: 32, height: 32)
            Image(systemName: locationType.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .scaleEffect(isFocused ? 1.2 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Sighting Pin

private struct SightingMapPin: View {
    var isFocused: Bool = false

    var body: some View {
        ZStack {
            if isFocused {
                Circle()
                    .strokeBorder(.white, lineWidth: 2.5)
                    .frame(width: 32, height: 32)
                    .shadow(color: Color.pink.opacity(0.5), radius: 5)
            }
            Circle()
                .fill(Color.pink.opacity(isFocused ? 1.0 : 0.9))
                .frame(width: 26, height: 26)
            Image(systemName: "eye.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .scaleEffect(isFocused ? 1.2 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - iNaturalist Pin

private struct InatMapPin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.teal.opacity(0.9))
                .frame(width: 24, height: 24)
            Image(systemName: "binoculars.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - iNaturalist Observation Detail

@available(iOS 16.0, macOS 13.0, *)
private struct InatObservationDetailView: View {
    let observation: iNaturalistObservation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let photoURL = observation.photoURL {
                        AsyncImage(url: photoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 220)
                                    .clipped()
                            case .failure:
                                Rectangle()
                                    .fill(Color.teal.opacity(0.15))
                                    .frame(height: 220)
                                    .overlay { Image(systemName: "binoculars.fill").font(.largeTitle).foregroundStyle(.teal) }
                            case .empty:
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(height: 220)
                                    .overlay { ProgressView() }
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .cornerRadius(12)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(observation.displayName)
                            .font(.title2.bold())
                        if observation.commonName != nil {
                            Text(observation.taxonName)
                                .font(.subheadline.italic())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    if let date = observation.observedOn {
                        LabeledContent("Observed", value: date)
                    }

                    if let url = observation.wikiURL {
                        Link(destination: url) {
                            Label("Wikipedia", systemImage: "book.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.gray)
                    }
                    if let url = observation.observationURL {
                        Link(destination: url) {
                            Label("View on iNaturalist", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                    }
                }
                .padding()
            }
            .navigationTitle("Wildlife Sighting")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Modern Map (iOS 17+ / macOS 14+)

@available(iOS 17.0, macOS 14.0, *)
private struct ModernTripMapView: View {
    let coordinatedLocations: [(index: Int, location: TripLocation, coord: CLLocationCoordinate2D)]
    let coordinatedSightings: [(sighting: TripVisit, coord: CLLocationCoordinate2D)]
    let initialRegion: MKCoordinateRegion
    let focusedLocationId: String?
    let focusedSightingIds: Set<String>
    let mapStyle: TripMapStyle
    let showInatOverlay: Bool
    let inatTaxonFilter: InatTaxonFilter
    let onLocationTapped: ((String) -> Void)?
    let onSightingTapped: ((String) -> Void)?
    let onMapLongPress: ((CLLocationCoordinate2D) -> Void)?
    let onSightingLongPress: ((CLLocationCoordinate2D) -> Void)?

    @State private var cameraPosition: MapCameraPosition
    @State private var currentRegion: MKCoordinateRegion
    @State private var inatObservations: [iNaturalistObservation] = []
    @State private var selectedInatObs: iNaturalistObservation? = nil
    #if os(macOS)
    @State private var hoveredCoord: CLLocationCoordinate2D?
    #endif

    init(
        coordinatedLocations: [(index: Int, location: TripLocation, coord: CLLocationCoordinate2D)],
        coordinatedSightings: [(sighting: TripVisit, coord: CLLocationCoordinate2D)],
        initialRegion: MKCoordinateRegion,
        focusedLocationId: String?,
        focusedSightingIds: Set<String>,
        mapStyle: TripMapStyle,
        showInatOverlay: Bool,
        inatTaxonFilter: InatTaxonFilter,
        onLocationTapped: ((String) -> Void)?,
        onSightingTapped: ((String) -> Void)?,
        onMapLongPress: ((CLLocationCoordinate2D) -> Void)?,
        onSightingLongPress: ((CLLocationCoordinate2D) -> Void)?
    ) {
        self.coordinatedLocations = coordinatedLocations
        self.coordinatedSightings = coordinatedSightings
        self.initialRegion = initialRegion
        self.focusedLocationId = focusedLocationId
        self.focusedSightingIds = focusedSightingIds
        self.mapStyle = mapStyle
        self.showInatOverlay = showInatOverlay
        self.inatTaxonFilter = inatTaxonFilter
        self.onLocationTapped = onLocationTapped
        self.onSightingTapped = onSightingTapped
        self.onMapLongPress = onMapLongPress
        self.onSightingLongPress = onSightingLongPress
        // Start the camera at the region that fits all locations so that annotations
        // are within the viewport and render immediately. The .task below then
        // smoothly animates to the focused pin.
        _cameraPosition  = State(initialValue: .region(initialRegion))
        _currentRegion   = State(initialValue: initialRegion)
    }

    /// Task id that changes whenever we need to (re-)fetch iNat observations.
    /// Coordinates are rounded to ~1 km precision to avoid over-fetching on tiny pans.
    private var inatFetchId: String {
        let lat = String(format: "%.2f", currentRegion.center.latitude)
        let lng = String(format: "%.2f", currentRegion.center.longitude)
        return "\(showInatOverlay)-\(inatTaxonFilter.rawValue)-\(lat)-\(lng)"
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                ForEach(coordinatedLocations, id: \.location.id) { item in
                    Annotation(item.location.name, coordinate: item.coord, anchor: .center) {
                        Button { onLocationTapped?(item.location.id) } label: {
                            TripMapPin(
                                locationType: item.location.type,
                                isFocused: item.location.id == focusedLocationId
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Sighting pins
                ForEach(coordinatedSightings, id: \.sighting.id) { item in
                    let label = item.sighting.sightings.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
                    Annotation(label.isEmpty ? "Sighting" : label, coordinate: item.coord, anchor: .center) {
                        Button {
                            onSightingTapped?(item.sighting.id)
                        } label: {
                            SightingMapPin(isFocused: focusedSightingIds.contains(item.sighting.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                // iNaturalist overlay pins
                if showInatOverlay {
                    ForEach(inatObservations) { obs in
                        Annotation(obs.displayName, coordinate: obs.coordinate, anchor: .center) {
                            Button { selectedInatObs = obs } label: {
                                InatMapPin()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .mapStyle(mapStyle.mapStyle)
            #if os(macOS)
            .mapControls {
                MapZoomStepper()
                MapCompass()
            }
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    hoveredCoord = proxy.convert(location, from: .local)
                }
            }
            .contextMenu {
                if onMapLongPress != nil {
                    Button("New Location Here") {
                        if let coord = hoveredCoord { onMapLongPress?(coord) }
                    }
                }
                if onSightingLongPress != nil {
                    Button("New Sighting Here") {
                        if let coord = hoveredCoord { onSightingLongPress?(coord) }
                    }
                }
            }
            #else
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        if case .second(true, let drag) = value,
                           let location = drag?.location,
                           let coord = proxy.convert(location, from: .local) {
                            onMapLongPress?(coord)
                        }
                    }
            )
            #endif
            // After MapKit finishes its first layout pass, animate to the focused pin.
            // The transition from the world-view initial position guarantees MapKit
            // triggers a full annotation-layer render.
            .task(id: focusedLocationId) {
                guard let id = focusedLocationId,
                      let item = coordinatedLocations.first(where: { $0.location.id == id })
                else { return }
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: item.coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                }
            }
            .task(id: focusedSightingIds) {
                guard !focusedSightingIds.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                let focused = coordinatedSightings.filter { focusedSightingIds.contains($0.sighting.id) }
                guard !focused.isEmpty else { return }
                if focused.count == 1 {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: focused[0].coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        ))
                    }
                } else {
                    let lats = focused.map { $0.coord.latitude }
                    let lons = focused.map { $0.coord.longitude }
                    let center = CLLocationCoordinate2D(
                        latitude: ((lats.min()! + lats.max()!) / 2),
                        longitude: ((lons.min()! + lons.max()!) / 2)
                    )
                    let span = MKCoordinateSpan(
                        latitudeDelta: (lats.max()! - lats.min()!) * 1.5 + 0.05,
                        longitudeDelta: (lons.max()! - lons.min()!) * 1.5 + 0.05
                    )
                    withAnimation(.easeInOut(duration: 0.4)) {
                        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
                    }
                }
            }
            #if os(macOS)
            .overlay(alignment: .center) {
                Button("") {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        cameraPosition = .region(initialRegion)
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
            }
            #endif
            .onMapCameraChange(frequency: .onEnd) { context in
                currentRegion = context.region
            }
            .task(id: inatFetchId) {
                guard showInatOverlay else {
                    inatObservations = []
                    return
                }
                // Brief debounce so rapid pans don't fire many requests.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                if let obs = try? await INaturalistService.fetchObservations(
                    in: currentRegion, taxonFilter: inatTaxonFilter
                ) {
                    inatObservations = obs
                }
            }
            .sheet(item: $selectedInatObs) { obs in
                InatObservationDetailView(observation: obs)
            }
        }
    }
}

// MARK: - Legacy representable (pre-iOS 17 / macOS 14)

private struct TripMapLegacyView {
    let region: MKCoordinateRegion
    let coordinatedLocations: [(index: Int, location: TripLocation, coord: CLLocationCoordinate2D)]
    let focusedLocationId: String?
    let mapStyle: TripMapStyle
    let onLocationTapped: ((String) -> Void)?
}

#if os(iOS)
extension TripMapLegacyView: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onLocationTapped = onLocationTapped
        mapView.mapType = mapStyle.legacyMapType
        let ids = coordinatedLocations.map { $0.location.id }
        if context.coordinator.lastLocationIds != ids {
            context.coordinator.lastLocationIds = ids
            mapView.setRegion(region, animated: false)
        }
        mapView.removeAnnotations(mapView.annotations)
        mapView.addAnnotations(coordinatedLocations.map {
            NumberedAnnotation(coordinate: $0.coord, title: $0.location.name, number: $0.index + 1, locationId: $0.location.id)
        })
        focusIfNeeded(context: context)
    }

    func makeCoordinator() -> MapCoordinator { MapCoordinator() }
}
#else
extension TripMapLegacyView: NSViewRepresentable {
    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        context.coordinator.mapView = mapView
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onLocationTapped = onLocationTapped
        mapView.mapType = mapStyle.legacyMapType
        let ids = coordinatedLocations.map { $0.location.id }
        if context.coordinator.lastLocationIds != ids {
            context.coordinator.lastLocationIds = ids
            mapView.setRegion(region, animated: false)
        }
        mapView.removeAnnotations(mapView.annotations)
        mapView.addAnnotations(coordinatedLocations.map {
            NumberedAnnotation(coordinate: $0.coord, title: $0.location.name, number: $0.index + 1, locationId: $0.location.id)
        })
        focusIfNeeded(context: context)
    }

    func makeCoordinator() -> MapCoordinator { MapCoordinator() }
}
#endif

extension TripMapLegacyView {
    func focusIfNeeded(context: Context) {
        guard let newId = focusedLocationId,
              context.coordinator.lastFocusedId != newId,
              let item = coordinatedLocations.first(where: { $0.location.id == newId }) else { return }
        context.coordinator.lastFocusedId = newId
        let focusRegion = MKCoordinateRegion(
            center: item.coord,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        context.coordinator.mapView?.setRegion(focusRegion, animated: true)
    }
}

private class NumberedAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let number: Int
    let locationId: String

    init(coordinate: CLLocationCoordinate2D, title: String, number: Int, locationId: String) {
        self.coordinate = coordinate
        self.title = title
        self.number = number
        self.locationId = locationId
    }
}

private class MapCoordinator: NSObject, MKMapViewDelegate {
    var lastLocationIds: [String] = []
    var lastFocusedId: String? = nil
    weak var mapView: MKMapView?
    var onLocationTapped: ((String) -> Void)?

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let numbered = annotation as? NumberedAnnotation else { return nil }
        let id = "numbered"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
        view.annotation = annotation
        view.glyphText = "\(numbered.number)"
        view.markerTintColor = .systemBlue
        view.canShowCallout = true
        return view
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let numbered = view.annotation as? NumberedAnnotation else { return }
        onLocationTapped?(numbered.locationId)
        mapView.deselectAnnotation(view.annotation, animated: false)
    }
}
