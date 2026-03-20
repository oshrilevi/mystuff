import SwiftUI
import MapKit

struct TripMapView: View {
    let locations: [TripLocation]
    var focusedLocationId: String? = nil
    var onLocationTapped: ((String) -> Void)? = nil

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
        if #available(iOS 17.0, macOS 14.0, *) {
            ModernTripMapView(
                coordinatedLocations: coordinatedLocations,
                initialRegion: boundingRegion,
                focusedLocationId: focusedLocationId,
                onLocationTapped: onLocationTapped
            )
        } else {
            TripMapLegacyView(
                region: boundingRegion,
                coordinatedLocations: coordinatedLocations,
                focusedLocationId: focusedLocationId,
                onLocationTapped: onLocationTapped
            )
        }
    }
}

// MARK: - Pin View (extracted to avoid compiler type-check timeout)

private struct TripMapPin: View {
    let index: Int
    let isFocused: Bool
    let onTap: () -> Void

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
        .onTapGesture { onTap() }
    }
}

// MARK: - Modern Map (iOS 17+ / macOS 14+)

@available(iOS 17.0, macOS 14.0, *)
private struct ModernTripMapView: View {
    let coordinatedLocations: [(index: Int, location: TripLocation, coord: CLLocationCoordinate2D)]
    let initialRegion: MKCoordinateRegion
    let focusedLocationId: String?
    let onLocationTapped: ((String) -> Void)?

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(coordinatedLocations, id: \.location.id) { item in
                Annotation(item.location.name, coordinate: item.coord) {
                    TripMapPin(
                        index: item.index,
                        isFocused: item.location.id == focusedLocationId,
                        onTap: { onLocationTapped?(item.location.id) }
                    )
                }
            }
        }
        #if os(macOS)
        .mapControls {
            MapZoomStepper()
            MapCompass()
        }
        #endif
        .onAppear {
            cameraPosition = .region(initialRegion)
        }
        .onChange(of: focusedLocationId) { _, newId in
            guard let newId,
                  let item = coordinatedLocations.first(where: { $0.location.id == newId }) else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: item.coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }
    }
}

// MARK: - Legacy representable (pre-iOS 17 / macOS 14)

private struct TripMapLegacyView {
    let region: MKCoordinateRegion
    let coordinatedLocations: [(index: Int, location: TripLocation, coord: CLLocationCoordinate2D)]
    let focusedLocationId: String?
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
