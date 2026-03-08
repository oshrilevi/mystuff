import SwiftUI

/// Preset hex colors for category header, grouped by family. Stored in Sheets as hex string.
/// Each row is a color family with shades from light to dark.
private let categoryColorPresetRows: [(section: String, presets: [(label: String, hex: String?)])] = [
    ("None", [
        ("None", nil),
    ]),
    ("Reds", [
        ("Light", "#FFCDD2"),
        ("", "#EF9A9A"),
        ("", "#E57373"),
        ("", "#EF5350"),
        ("", "#F44336"),
        ("Dark", "#C62828"),
        ("Darker", "#B71C1C"),
    ]),
    ("Yellows", [
        ("Light", "#FFF9C4"),
        ("", "#FFF59D"),
        ("", "#FFF176"),
        ("", "#FFEE58"),
        ("", "#FFEB3B"),
        ("Dark", "#FBC02D"),
        ("Darker", "#F9A825"),
    ]),
    ("Greens", [
        ("Light", "#C8E6C9"),
        ("", "#A5D6A7"),
        ("", "#81C784"),
        ("", "#66BB6A"),
        ("", "#4CAF50"),
        ("Dark", "#2E7D32"),
        ("Darker", "#1B5E20"),
    ]),
    ("Blues", [
        ("Light", "#B3E5FC"),
        ("", "#81D4FA"),
        ("", "#4FC3F7"),
        ("", "#29B6F6"),
        ("", "#03A9F4"),
        ("Dark", "#1565C0"),
        ("Darker", "#0D47A1"),
    ]),
    ("Purples", [
        ("Light", "#E1BEE7"),
        ("", "#CE93D8"),
        ("", "#BA68C8"),
        ("", "#AB47BC"),
        ("", "#9C27B0"),
        ("Dark", "#6A1B9A"),
        ("Darker", "#4A148C"),
    ]),
    ("Browns", [
        ("Light", "#D7CCC8"),
        ("", "#BCAAA4"),
        ("", "#A1887F"),
        ("", "#8D6E63"),
        ("", "#795548"),
        ("Dark", "#5D4037"),
        ("Darker", "#3E2723"),
    ]),
]

struct CategoriesView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService
    @State private var newCategoryName = ""
    @State private var showAdd = false
    @State private var editingCategory: Category?

    private var categoriesVM: CategoriesViewModel { session.categories }

    private var sortedCategories: [Category] {
        categoriesVM.categories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if categoriesVM.isLoading, categoriesVM.categories.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let err = categoriesVM.errorMessage {
                            Section {
                                Text(err).foregroundStyle(.red)
                            }
                        }
                        ForEach(sortedCategories) { cat in
                            HStack(spacing: 12) {
                                if let hex = cat.color, let color = Color(hex: hex) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(color)
                                        .frame(width: 20, height: 20)
                                }
                                Text(cat.name)
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .contentShape(Rectangle())
                            .onTapGesture { beginEdit(cat) }
                        }
                        .onDelete(perform: deleteCategories)
                    }
                    .refreshable { await categoriesVM.load() }
                }
            }
            .navigationTitle("Categories")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                            .help("Add category")
                        UserAvatarMenuView()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                            .help("Add category")
                        UserAvatarMenuView()
                    }
                }
                #endif
            }
            .alert("New category", isPresented: $showAdd) {
                TextField("Name", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Add") {
                    let name = newCategoryName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        Task { await categoriesVM.addCategory(name: name) }
                        newCategoryName = ""
                    }
                }
            } message: {
                Text("Enter category name")
            }
            .sheet(item: $editingCategory) { cat in
                EditCategorySheet(
                    category: cat,
                    categoriesVM: categoriesVM,
                    onDismiss: { editingCategory = nil }
                )
            }
            .task { await categoriesVM.load() }
        }
    }

    private func beginEdit(_ cat: Category) {
        editingCategory = cat
    }

    private func deleteCategories(at offsets: IndexSet) {
        let ids = offsets.map { sortedCategories[$0].id }
        Task { await categoriesVM.deleteCategory(ids: ids) }
    }
}

private struct EditCategorySheet: View {
    let category: Category
    let categoriesVM: CategoriesViewModel
    let onDismiss: () -> Void

    @State private var name: String
    @State private var selectedColor: String?

    init(category: Category, categoriesVM: CategoriesViewModel, onDismiss: @escaping () -> Void) {
        self.category = category
        self.categoriesVM = categoriesVM
        self.onDismiss = onDismiss
        _name = State(initialValue: category.name)
        _selectedColor = State(initialValue: category.color)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .labelsHidden()
                } header: {
                    Text("Name")
                }
                Section {
                    Text("Used as the section header background in the Items list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(categoryColorPresetRows.enumerated()), id: \.offset) { _, row in
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: row.presets.count), spacing: 12) {
                            ForEach(Array(row.presets.enumerated()), id: \.offset) { presetIndex, preset in
                                let presetId = "\(row.section)-\(presetIndex)-\(preset.hex ?? "none")"
                                let isSelected = selectedColor == preset.hex
                                Button {
                                    selectedColor = preset.hex
                                } label: {
                                    if let hex = preset.hex, let color = Color(hex: hex) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(color)
                                            .frame(height: 36)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                                            )
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(.quaternary)
                                            .frame(height: 36)
                                            .overlay(
                                                Text("None")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                                .id(presetId)
                            }
                        }
                    }
                } header: {
                    Text("Header color")
                }
            }
            .formStyle(.grouped)
            .padding(24)
            .frame(width: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .navigationTitle("Edit category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .help("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            Task {
                                await categoriesVM.updateCategory(id: category.id, name: trimmed, color: selectedColor)
                            }
                        }
                        onDismiss()
                    }
                    .help("Save")
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Color from hex (used by category header and section headers)
extension Color {
    /// Creates a Color from a hex string (e.g. "#FF5733" or "FF5733"). Returns nil if invalid.
    init?(hex: String?) {
        guard let hex = hex?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else { return nil }
        var hexSanitized = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if hexSanitized.count == 6 { }
        else if hexSanitized.count == 8 { hexSanitized = String(hexSanitized.prefix(6)) }
        else { return nil }
        guard let value = UInt64(hexSanitized, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
