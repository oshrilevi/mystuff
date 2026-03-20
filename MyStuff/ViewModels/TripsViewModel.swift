import Foundation

@MainActor
final class TripsViewModel: ObservableObject {
    @Published var trips: [Trip] = []
    @Published var tripLocations: [TripLocation] = []
    @Published var tripVisits: [TripVisit] = []
    @Published var searchText: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sheets: SheetsService
    private var spreadsheetId: String? { appState.spreadsheetId }
    private let appState: AppState

    init(sheets: SheetsService, appState: AppState) {
        self.sheets = sheets
        self.appState = appState
    }

    var filteredTrips: [Trip] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return trips.sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
        }
        let q = searchText.lowercased()
        return trips
            .filter { trip in
                trip.name.lowercased().contains(q) ||
                trip.description.lowercased().contains(q) ||
                trip.tags.joined(separator: " ").lowercased().contains(q)
            }
            .sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    func locations(for trip: Trip) -> [TripLocation] {
        let byId = Dictionary(uniqueKeysWithValues: tripLocations.map { ($0.id, $0) })
        return trip.locationIds.compactMap { byId[$0] }
    }

    func visits(for trip: Trip) -> [TripVisit] {
        tripVisits
            .filter { $0.tripId == trip.id }
            .sorted { $0.date > $1.date }
    }

    func visits(for trip: Trip, at location: TripLocation) -> [TripVisit] {
        tripVisits
            .filter { $0.tripId == trip.id && $0.locationId == location.id }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Load

    func load() async {
        guard let sid = spreadsheetId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            let tripRows = try await sheets.getValues(spreadsheetId: sid, range: "Trips!A2:Z1000")
            let locationRows = try await sheets.getValues(spreadsheetId: sid, range: "TripLocations!A2:Z1000")
            let visitRows = try await sheets.getValues(spreadsheetId: sid, range: "TripVisits!A2:Z5000")
            trips = parseTripRows(tripRows)
            tripLocations = parseTripLocationRows(locationRows)
            tripVisits = parseTripVisitRows(visitRows)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Trips CRUD

    func addTrip(name: String, description: String = "", tags: [String] = [], locationIds: [String] = []) async {
        guard let sid = spreadsheetId else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let nextOrder = (trips.map { $0.order }.max() ?? 0) + 1
        let trip = Trip(
            id: UUID().uuidString,
            name: trimmed,
            description: description,
            tags: tags,
            locationIds: locationIds,
            order: nextOrder,
            createdAt: now,
            updatedAt: now
        )
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Trips", values: [tripToRow(trip)])
            trips.append(trip)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTrip(_ trip: Trip) async {
        guard let sid = spreadsheetId else { return }
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        var updated = trip
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        var updatedTrips = trips
        updatedTrips[index] = updated
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Trips")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Trips", values: [Trip.columnOrder])
            if !updatedTrips.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Trips", values: updatedTrips.map { tripToRow($0) })
            }
            trips = updatedTrips
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTrips(_ tripsToDelete: [Trip]) async {
        guard let sid = spreadsheetId else { return }
        let ids = Set(tripsToDelete.map { $0.id })
        let remainingTrips = trips.filter { !ids.contains($0.id) }
        let remainingVisits = tripVisits.filter { !ids.contains($0.tripId) }
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Trips")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Trips", values: [Trip.columnOrder])
            if !remainingTrips.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Trips", values: remainingTrips.map { tripToRow($0) })
            }
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "TripVisits")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripVisits", values: [TripVisit.columnOrder])
            if !remainingVisits.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripVisits", values: remainingVisits.map { tripVisitToRow($0) })
            }
            trips = remainingTrips
            tripVisits = remainingVisits
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - TripLocation CRUD

    func addTripLocation(name: String, description: String = "", tags: [String] = [], latitude: Double? = nil, longitude: Double? = nil) async {
        guard let sid = spreadsheetId else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let loc = TripLocation(
            id: UUID().uuidString,
            name: trimmed,
            description: description,
            tags: tags,
            latitude: latitude,
            longitude: longitude,
            createdAt: now,
            updatedAt: now
        )
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripLocations", values: [tripLocationToRow(loc)])
            tripLocations.append(loc)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTripLocation(_ location: TripLocation) async {
        guard let sid = spreadsheetId else { return }
        guard let index = tripLocations.firstIndex(where: { $0.id == location.id }) else { return }
        var updated = location
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        var updatedLocations = tripLocations
        updatedLocations[index] = updated
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "TripLocations")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripLocations", values: [TripLocation.columnOrder])
            if !updatedLocations.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripLocations", values: updatedLocations.map { tripLocationToRow($0) })
            }
            tripLocations = updatedLocations
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTripLocations(ids: Set<String>) async {
        guard let sid = spreadsheetId else { return }
        let remainingLocations = tripLocations.filter { !ids.contains($0.id) }
        // Remove deleted locations from all trips' locationIds
        var updatedTrips = trips.map { trip -> Trip in
            var t = trip
            t.locationIds = t.locationIds.filter { !ids.contains($0) }
            return t
        }
        let remainingVisits = tripVisits.filter { !ids.contains($0.locationId) }
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "TripLocations")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripLocations", values: [TripLocation.columnOrder])
            if !remainingLocations.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripLocations", values: remainingLocations.map { tripLocationToRow($0) })
            }
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "Trips")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Trips", values: [Trip.columnOrder])
            if !updatedTrips.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "Trips", values: updatedTrips.map { tripToRow($0) })
            }
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "TripVisits")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripVisits", values: [TripVisit.columnOrder])
            if !remainingVisits.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripVisits", values: remainingVisits.map { tripVisitToRow($0) })
            }
            tripLocations = remainingLocations
            trips = updatedTrips
            tripVisits = remainingVisits
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - TripVisit CRUD

    func addVisit(tripId: String, locationId: String, date: String, summary: String, tags: [String] = []) async {
        guard let sid = spreadsheetId else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let visit = TripVisit(
            id: UUID().uuidString,
            tripId: tripId,
            locationId: locationId,
            date: date,
            summary: summary,
            tags: tags,
            createdAt: now,
            updatedAt: now
        )
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripVisits", values: [tripVisitToRow(visit)])
            tripVisits.append(visit)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateVisit(_ visit: TripVisit) async {
        guard let sid = spreadsheetId else { return }
        guard let index = tripVisits.firstIndex(where: { $0.id == visit.id }) else { return }
        var updated = visit
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        var updatedVisits = tripVisits
        updatedVisits[index] = updated
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "TripVisits")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripVisits", values: [TripVisit.columnOrder])
            if !updatedVisits.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripVisits", values: updatedVisits.map { tripVisitToRow($0) })
            }
            tripVisits = updatedVisits
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteVisit(id: String) async {
        guard let sid = spreadsheetId else { return }
        let remaining = tripVisits.filter { $0.id != id }
        do {
            try await ensureSheetsExist(spreadsheetId: sid)
            try await sheets.clearSheet(spreadsheetId: sid, sheetName: "TripVisits")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripVisits", values: [TripVisit.columnOrder])
            if !remaining.isEmpty {
                try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripVisits", values: remaining.map { tripVisitToRow($0) })
            }
            tripVisits = remaining
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sheet Migration

    private func ensureSheetsExist(spreadsheetId sid: String) async throws {
        let titles = try await sheets.getSheetTitles(spreadsheetId: sid)
        if !titles.contains("TripLocations") {
            try await sheets.addSheet(spreadsheetId: sid, title: "TripLocations")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripLocations", values: [TripLocation.columnOrder])
        }
        if !titles.contains("Trips") {
            try await sheets.addSheet(spreadsheetId: sid, title: "Trips")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "Trips", values: [Trip.columnOrder])
        }
        if !titles.contains("TripVisits") {
            try await sheets.addSheet(spreadsheetId: sid, title: "TripVisits")
            try await sheets.appendRows(spreadsheetId: sid, sheetName: "TripVisits", values: [TripVisit.columnOrder])
        }
    }

    // MARK: - Serialization

    private func tripToRow(_ trip: Trip) -> [String] {
        [
            trip.id,
            trip.name,
            trip.description,
            trip.tags.joined(separator: ","),
            trip.locationIds.joined(separator: ","),
            "\(trip.order)",
            trip.createdAt,
            trip.updatedAt
        ]
    }

    private func parseTripRows(_ rows: [[String]]) -> [Trip] {
        rows.enumerated().compactMap { index, row in
            guard row.count >= 2 else { return nil }
            let description = row.count > 2 ? row[2] : ""
            let tags = row.count > 3 ? parseTags(row[3]) : []
            let locationIds = row.count > 4 ? parseIds(row[4]) : []
            let order = row.count > 5 ? (Int(row[5]) ?? index + 2) : index + 2
            let createdAt = row.count > 6 ? row[6] : ""
            let updatedAt = row.count > 7 ? row[7] : ""
            return Trip(
                id: row[0],
                name: row[1],
                description: description,
                tags: tags,
                locationIds: locationIds,
                order: order,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private func tripLocationToRow(_ loc: TripLocation) -> [String] {
        [
            loc.id,
            loc.name,
            loc.description,
            loc.tags.joined(separator: ","),
            loc.latitude.map { "\($0)" } ?? "",
            loc.longitude.map { "\($0)" } ?? "",
            loc.createdAt,
            loc.updatedAt
        ]
    }

    private func parseTripLocationRows(_ rows: [[String]]) -> [TripLocation] {
        rows.compactMap { row in
            guard row.count >= 2 else { return nil }
            let description = row.count > 2 ? row[2] : ""
            let tags = row.count > 3 ? parseTags(row[3]) : []
            let latitude = row.count > 4 ? Double(row[4]) : nil
            let longitude = row.count > 5 ? Double(row[5]) : nil
            let createdAt = row.count > 6 ? row[6] : ""
            let updatedAt = row.count > 7 ? row[7] : ""
            return TripLocation(
                id: row[0],
                name: row[1],
                description: description,
                tags: tags,
                latitude: latitude,
                longitude: longitude,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private func tripVisitToRow(_ visit: TripVisit) -> [String] {
        [
            visit.id,
            visit.tripId,
            visit.locationId,
            visit.date,
            visit.summary,
            visit.tags.joined(separator: ","),
            visit.createdAt,
            visit.updatedAt
        ]
    }

    private func parseTripVisitRows(_ rows: [[String]]) -> [TripVisit] {
        rows.compactMap { row in
            guard row.count >= 4 else { return nil }
            let summary = row.count > 4 ? row[4] : ""
            let tags = row.count > 5 ? parseTags(row[5]) : []
            let createdAt = row.count > 6 ? row[6] : ""
            let updatedAt = row.count > 7 ? row[7] : ""
            return TripVisit(
                id: row[0],
                tripId: row[1],
                locationId: row[2],
                date: row[3],
                summary: summary,
                tags: tags,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private func parseTags(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func parseIds(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
