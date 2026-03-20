import SwiftUI

struct TripVisitFormSheet: View {
    let visit: TripVisit?
    let locations: [TripLocation]
    let onSave: (String, String, String, [String]) -> Void

    @State private var selectedLocationId: String
    @State private var date: Date
    @State private var summary: String
    @State private var tags: [String]
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(visit: TripVisit?, locations: [TripLocation], onSave: @escaping (String, String, String, [String]) -> Void) {
        self.visit = visit
        self.locations = locations
        self.onSave = onSave
        _selectedLocationId = State(initialValue: visit?.locationId ?? locations.first?.id ?? "")
        _date = State(initialValue: {
            if let dateStr = visit?.date, let d = Self.dateFormatter.date(from: dateStr) { return d }
            return Date()
        }())
        _summary = State(initialValue: visit?.summary ?? "")
        _tags = State(initialValue: visit?.tags ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    if locations.isEmpty {
                        Text("No locations in this trip. Add a location first.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Location", selection: $selectedLocationId) {
                            ForEach(locations) { loc in
                                Text(loc.name).tag(loc.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
                Section("Summary") {
                    TextField("What did you see or do?", text: $summary, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Tags") {
                    TagChipsEditor(tags: $tags)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(visit == nil ? "New Visit" : "Edit Visit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let dateStr = Self.dateFormatter.string(from: date)
                        onSave(selectedLocationId, dateStr, summary, tags)
                        dismiss()
                    }
                    .disabled(selectedLocationId.isEmpty || locations.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}
