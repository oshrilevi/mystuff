import SwiftUI

struct ComboPickerView: View {
    @EnvironmentObject var session: Session

    /// Snapshot of all available combos at the time the picker is presented.
    let combos: [Combo]
    let onDone: ([Combo]) -> Void
    let onCancel: () -> Void

    @State private var selectedIds: Set<String> = []
    @State private var searchText: String = ""

    private var filteredCombos: [Combo] {
        var result = combos
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let q = trimmed.lowercased()
            result = result.filter { combo in
                combo.name.lowercased().contains(q)
                || combo.notes.lowercased().contains(q)
            }
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    searchField
                }
                if filteredCombos.isEmpty {
                    Section {
                        Text("No combos available yet. Create combos from the Combos section first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                } else {
                    ForEach(Array(filteredCombos.enumerated()), id: \.element.id) { _, combo in
                        Button {
                            toggleSelection(for: combo)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: selectedIds.contains(combo.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIds.contains(combo.id) ? Color.accentColor : .secondary)
                                    .frame(width: 24, height: 32, alignment: .center)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(combo.name)
                                        .font(.body)
                                    if !combo.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(combo.notes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    let itemsInCombo = session.combos.items(for: combo, from: session.inventory.items)
                                    if !itemsInCombo.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 6) {
                                                ForEach(itemsInCombo.prefix(6)) { item in
                                                    ItemThumbnailView(
                                                        drive: session.drive,
                                                        photoId: item.photoIds.first,
                                                        size: 32,
                                                        cornerRadius: 6,
                                                        placeholderFont: .caption
                                                    )
                                                }
                                            }
                                            .padding(.top, 2)
                                        }
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add Combos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let selectedCombos = combos.filter { selectedIds.contains($0.id) }
                        onDone(selectedCombos)
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
        #endif
    }

    private func toggleSelection(for combo: Combo) {
        if selectedIds.contains(combo.id) {
            selectedIds.remove(combo.id)
        } else {
            selectedIds.insert(combo.id)
        }
    }

    private var searchField: some View {
        ZStack(alignment: .trailing) {
            TextField("Search combos", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160, maxWidth: 260)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

