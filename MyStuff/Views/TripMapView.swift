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
    var focusedLocationId: String? = nil
    var onLocationTapped: ((String) -> Void)? = nil
    var onMapLongPress: ((CLLocationCoordinate2D) -> Void)? = nil

    @AppStorage("tripMapStyle") private var mapStyle: TripMapStyle = .standard

    private var coordinatedLocations: [(index: Int, location: TripLocation, coord: CLLocationCoordinate2D)] {
        locations.enumerated().compactMap { idx, loc in
            guard let lat = loc.latitude, let lon = loc.longitude else { return nil }
            return (idx, loc, CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    private var boundingRegion: MKCoordinateRegion {
        let coords = coordinatedLocations.map { $0.coord }
        guard !coords.isEmpty else {
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
        ZStack(alignment: .topTrailing) {
            if #available(iOS 17.0, macOS 14.0, *) {
                ModernTripMapView(
                    coordinatedLocations: coordinatedLocations,
                    initialRegion: boundingRegion,
                    focusedLocationId: focusedLocationId,
                    mapStyle: mapStyle,
                    onLocationTapped: onLocationTapped,
                    onMapLongPress: onMapLongPress
                )
                // Force full recreation when the set of locations changes so MapKit
                // correctly renders all annotations from the start.
                .id(coordinatedLocations.map(\.location.id).joined(separator: ","))
            } else {
                TripMapLegacyView(
                    region: boundingRegion,
                    coordinatedLocations: coordinatedLocations,
                    focusedLocationId: focusedLocationId,
                    mapStyle: mapStyle,
                    onLocationTapped: onLocationTapped
                )
            }

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

// MARK: - Pin View (extracted to avoid compiler type-check timeout)

private struct TripMapPin: View {
    let index: Int
    let isFocused: Bool

    var body: some View {
        let pinColor: Color = isFocused ? .orange : .accentColor
        let shadowColor: Color = isFocused ? Color.orange.opacity(0.6) : .clear
        ZStack {
            Circle()
                .fill(pinColor)
                .frame(width: 28, height: 28)
                .shadow(color: shadowColor, radius: 5)
            Text("\(index + 1)")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Modern Map (iOS 17+ / macOS 14+)

@available(iOS 17.0, macOS 14.0, *)
private struct ModernTripMapView: View {
    let coordinatedLocations: [(index: Int, location: TripLocation, coord: CLLocationCoordinate2D)]
    let initialRegion: MKCoordinateRegion
    let focusedLocationId: String?
    let mapStyle: TripMapStyle
    let onLocationTapped: ((String) -> Void)?
    let onMapLongPress: ((CLLocationCoordinate2D) -> Void)?

    @State private var cameraPosition: MapCameraPosition
    #if os(macOS)
    @State private var hoveredCoord: CLLocationCoordinate2D?
    #endif

    init(
        coordinatedLocations: [(index: Int, location: TripLocation, coord: CLLocationCoordinate2D)],
        initialRegion: MKCoordinateRegion,
        focusedLocationId: String?,
        mapStyle: TripMapStyle,
        onLocationTapped: ((String) -> Void)?,
        onMapLongPress: ((CLLocationCoordinate2D) -> Void)?
    ) {
        self.coordinatedLocations = coordinatedLocations
        self.initialRegion = initialRegion
        self.focusedLocationId = focusedLocationId
        self.mapStyle = mapStyle
        self.onLocationTapped = onLocationTapped
        self.onMapLongPress = onMapLongPress
        // Start far-zoomed-out so the camera always makes a meaningful move to the
        // focused pin on appear — MapKit only renders annotation views after the
        // camera position state changes at least once post-appear.
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 180)
        )))
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                ForEach(coordinatedLocations, id: \.location.id) { item in
                    Annotation(item.location.name, coordinate: item.coord, anchor: .center) {
                        Button { onLocationTapped?(item.location.id) } label: {
                            TripMapPin(
                                index: item.index,
                                isFocused: item.location.id == focusedLocationId
                            )
                        }
                        .buttonStyle(.plain)
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
                        if let coord = hoveredCoord {
                            onMapLongPress?(coord)
                        }
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
