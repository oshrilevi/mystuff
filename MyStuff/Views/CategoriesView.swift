import SwiftUI

/// Preset hex colors for category header. Stored in Sheets as hex string.
private let categoryColorPresets: [(label: String, hex: String?)] = [
    ("None", nil),
    ("Red", "#E57373"),
    ("Deep red", "#C62828"),
    ("Orange", "#FFB74D"),
    ("Amber", "#FFC107"),
    ("Yellow", "#FFF176"),
    ("Lime", "#CDDC39"),
    ("Green", "#81C784"),
    ("Mint", "#4DB6AC"),
    ("Teal", "#4DD0E1"),
    ("Cyan", "#00BCD4"),
    ("Blue", "#64B5F6"),
    ("Indigo", "#5C6BC0"),
    ("Purple", "#9575CD"),
    ("Violet", "#7E57C2"),
    ("Pink", "#F06292"),
    ("Rose", "#EC407A"),
    ("Brown", "#8D6E63"),
    ("Gray", "#90A4AE"),
    ("Slate", "#607D8B"),
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
                        UserAvatarMenuView()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
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
                Section("Header color") {
                    Text("Used as the section header background in the Items list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                        ForEach(categoryColorPresets, id: \.label) { preset in
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
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(24)
            .frame(width: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .navigationTitle("Edit category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
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
