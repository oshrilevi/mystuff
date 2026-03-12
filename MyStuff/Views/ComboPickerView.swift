import SwiftUI

struct ComboPickerView: View {
    @EnvironmentObject var session: Session

    let onDone: ([Combo]) -> Void
    let onCancel: () -> Void

    @State private var selectedIds: Set<String> = []

    private var combosVM: CombosViewModel { session.combos }

    private var sortedCombos: [Combo] {
        combosVM.filteredCombos
    }

    var body: some View {
        NavigationStack {
            List {
                if sortedCombos.isEmpty {
                    Section {
                        Text("No combos available yet. Create combos from the Combos section first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                } else {
                    ForEach(Array(sortedCombos.enumerated()), id: \.element.id) { _, combo in
                        Button {
                            toggleSelection(for: combo)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(combo.name)
                                        .font(.body)
                                    if !combo.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(combo.notes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                if selectedIds.contains(combo.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.tertiary)
                                }
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
                        let selectedCombos = sortedCombos.filter { selectedIds.contains($0.id) }
                        onDone(selectedCombos)
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
        }
    }

    private func toggleSelection(for combo: Combo) {
        if selectedIds.contains(combo.id) {
            selectedIds.remove(combo.id)
        } else {
            selectedIds.insert(combo.id)
        }
    }
}

