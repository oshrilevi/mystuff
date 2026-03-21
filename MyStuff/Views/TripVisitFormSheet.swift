import SwiftUI
import MapKit // CLLocationCoordinate2D
import PhotosUI

struct TripVisitFormSheet: View {
    let visit: TripVisit?
    let initialCoordinate: CLLocationCoordinate2D?
    let onSave: ([VisitSighting], Double?, Double?, String, String, [String]) -> Void

    @State private var sightings: [VisitSighting]
    @State private var date: Date
    @State private var timeOfDay: TimeOfDay
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var photoIds: [String]
    @State private var pendingItems: [PhotosPickerItem] = []

    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    init(visit: TripVisit?, initialCoordinate: CLLocationCoordinate2D? = nil,
         onSave: @escaping ([VisitSighting], Double?, Double?, String, String, [String]) -> Void) {
        self.visit = visit
        self.initialCoordinate = initialCoordinate
        self.onSave = onSave

        _sightings = State(initialValue: visit?.sightings.isEmpty == false ? visit!.sightings : [VisitSighting(name: "")])
        _timeOfDay = State(initialValue: TimeOfDay(rawValue: visit?.timeOfDay ?? "") ?? .morning)
        _photoIds  = State(initialValue: visit?.photoIds ?? [])

        _date = State(initialValue: {
            if let s = visit?.date, let d = Self.dateFormatter.date(from: s) { return d }
            return Date()
        }())

        if let lat = visit?.latitude, let lon = visit?.longitude {
            _selectedCoordinate = State(initialValue: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        } else if let coord = initialCoordinate {
            _selectedCoordinate = State(initialValue: coord)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Observations
                Section {
                    ForEach($sightings) { $sighting in
                        SightingRowEditor(sighting: $sighting) {
                            sightings.removeAll { $0.id == sighting.id }
                        }
                    }
                    Button {
                        sightings.append(VisitSighting(name: ""))
                    } label: {
                        Label("Add Observation", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Observations")
                }

                // MARK: Date & Time of Day
                Section("Date & Time of Day") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Time of Day", selection: $timeOfDay) {
                        ForEach(TimeOfDay.allCases) { tod in
                            Text(tod.hebrewLabel).tag(tod)
                        }
                    }
                }

                // MARK: Photos
                Section("Photos") {
                    PhotosPicker(selection: $pendingItems, maxSelectionCount: 10, matching: .images) {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                    }
                    if !photoIds.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(photoIds, id: \.self) { id in
                                    ZStack(alignment: .topTrailing) {
                                                        PHAssetThumbnail(identifier: id, size: 72)
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                        Button {
                                            photoIds.removeAll { $0 == id }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                                .font(.system(size: 18))
                                        }
                                        .buttonStyle(.plain)
                                        .offset(x: 6, y: -6)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(visit == nil ? "New Sighting" : "Edit Sighting")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let dateStr = Self.dateFormatter.string(from: date)
                            let validSightings = sightings.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                            onSave(
                                validSightings,
                                selectedCoordinate?.latitude,
                                selectedCoordinate?.longitude,
                                dateStr,
                                timeOfDay.rawValue,
                                photoIds
                            )
                            dismiss()
                        }
                    }
                    .disabled(sightings.allSatisfy { $0.name.trimmingCharacters(in: .whitespaces).isEmpty })
                }
            }
            .onChange(of: pendingItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                let itemsToSave = newItems
                pendingItems = []
                Task {
                    for item in itemsToSave {
                        if let filename = await PhotoStorageService.save(item: item) {
                            photoIds.append(filename)
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

}

// MARK: - Sighting Row Editor

private struct SightingRowEditor: View {
    @Binding var sighting: VisitSighting
    let onRemove: () -> Void

    @State private var isFetchingWiki = false
    @State private var wikiTask: Task<Void, Never>?
    @State private var debounceTask: Task<Void, Never>?

    private var imageURL: URL? { URL(string: sighting.imageURL) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Thumbnail
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.1))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        TextField("Species or subject name", text: $sighting.name)
                            .onChange(of: sighting.name) { _, newName in scheduleWikiFetch(name: newName) }
                            .onAppear {
                                #if os(macOS)
                                // Keep focus but move cursor to end, clearing the auto-selection
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    if let editor = NSApp.keyWindow?.fieldEditor(false, for: nil) as? NSTextView {
                                        let end = editor.string.count
                                        editor.setSelectedRange(NSRange(location: end, length: 0))
                                    }
                                }
                                #endif
                            }
                        if isFetchingWiki { ProgressView().scaleEffect(0.7) }
                        Button(action: onRemove) {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    if !sighting.wikiDescription.isEmpty {
                        Text(sighting.wikiDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func scheduleWikiFetch(name: String) {
        debounceTask?.cancel()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            wikiTask?.cancel()
            isFetchingWiki = true
            sighting.wikiDescription = ""
            sighting.imageURL = ""
            wikiTask = Task {
                // Fetch wiki summary (description + thumbnail) and iNaturalist photo in parallel
                async let wikiResult = WikipediaService.fetchSummary(name: name)
                async let inatURL = INaturalistService.fetchPhotoURL(name: name)
                let (wiki, inat) = await (wikiResult, inatURL)
                guard !Task.isCancelled else { return }
                isFetchingWiki = false
                sighting.wikiDescription = wiki?.extract ?? ""
                sighting.wikiURL = wiki?.pageURL?.absoluteString ?? ""
                // Prefer iNaturalist photo (better for species); fall back to Wikipedia thumbnail
                let photoURL = inat ?? wiki?.thumbnailURL
                sighting.imageURL = photoURL?.absoluteString ?? ""
            }
        }
    }
}
