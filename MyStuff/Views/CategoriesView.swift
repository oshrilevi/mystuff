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
    @State private var showAddSheet = false
    @State private var showReorderSheet = false
    @State private var editingCategory: Category?
    @State private var pendingDeleteCategoryIds: [String] = []
    @State private var showDeleteConfirmation = false

    private var categoriesVM: CategoriesViewModel { session.categories }

    private struct CategoryRowModel: Identifiable {
        let id: String
        let category: Category
        let isChild: Bool
    }

    /// Flattened list of parent + child rows for display.
    private var categoryRows: [CategoryRowModel] {
        var rows: [CategoryRowModel] = []
        for parent in categoriesVM.topLevelCategories {
            rows.append(CategoryRowModel(id: parent.id, category: parent, isChild: false))
            if let children = categoriesVM.childrenByParentId[parent.id] {
                for child in children {
                    rows.append(CategoryRowModel(id: child.id, category: child, isChild: true))
                }
            }
        }
        return rows
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
                        if !categoriesVM.categories.isEmpty {
                            Text("Drag a category onto another to make it a subcategory. Drop on this row to make it top-level.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .dropDestination(for: String.self) { ids, _ in
                                    guard let id = ids.first else { return false }
                                    Task { await categoriesVM.setParent(childId: id, parentId: nil) }
                                    return true
                                }
                        }
                        ForEach(categoryRows) { row in
                            HStack(spacing: 12) {
                                if let hex = row.category.color, let color = Color(hex: hex) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(color)
                                        .frame(width: 20, height: 20)
                                }
                                Text(row.category.name)
                                    .font(row.isChild ? .subheadline : .body)
                                Spacer()
                                // Up/down buttons for both top-level and subcategories, within their group.
                                Button {
                                    moveCategory(row.category, direction: -1, isChild: row.isChild)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.plain)
                                .help("Move up")
                                Button {
                                    moveCategory(row.category, direction: 1, isChild: row.isChild)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.plain)
                                .help("Move down")
                                // Delete button for both parents and subcategories.
                                Button(role: .destructive) {
                                    deleteCategory(row.category)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .help("Delete category")
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: row.isChild ? 32 : 16, bottom: 10, trailing: 16))
                            .contentShape(Rectangle())
                            .onTapGesture { beginEdit(row.category) }
                            .draggable(row.category.id)
                            .dropDestination(for: String.self) { ids, _ in
                                // Only allow dropping onto parent rows to assign a child.
                                guard !row.isChild, let id = ids.first else { return false }
                                Task { await categoriesVM.setParent(childId: id, parentId: row.category.id) }
                                return true
                            }
                        }
                        .onDelete(perform: deleteCategories)
                    }
                    // Dropping a category anywhere on the list background makes it top-level.
                    .dropDestination(for: String.self) { ids, _ in
                        guard let id = ids.first else { return false }
                        Task { await categoriesVM.setParent(childId: id, parentId: nil) }
                        return true
                    }
                    .refreshable { await categoriesVM.load() }
                }
            }
            .navigationTitle("Categories")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showReorderSheet = true
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .help("Reorder top-level categories")
                        Button { showAddSheet = true } label: { Image(systemName: "plus") }
                            .help("Add category")
                        UserAvatarMenuView()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            showReorderSheet = true
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .help("Reorder top-level categories")
                        Button { showAddSheet = true } label: { Image(systemName: "plus") }
                            .help("Add category")
                        UserAvatarMenuView()
                    }
                }
                #endif
            }
            .sheet(isPresented: $showAddSheet) {
                NewCategorySheet(categoriesVM: categoriesVM) {
                    showAddSheet = false
                }
            }
            .sheet(isPresented: $showReorderSheet) {
                ReorderCategoriesSheet(categoriesVM: categoriesVM) {
                    showReorderSheet = false
                }
            }
            .sheet(item: $editingCategory) { cat in
                EditCategorySheet(
                    category: cat,
                    categoriesVM: categoriesVM,
                    onDismiss: { editingCategory = nil }
                )
            }
            .confirmationDialog(
                "Delete category?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    let ids = pendingDeleteCategoryIds
                    pendingDeleteCategoryIds = []
                    Task { await categoriesVM.deleteCategory(ids: ids) }
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteCategoryIds = []
                }
            } message: {
                Text("This cannot be undone. The category and any direct subcategories will be removed.")
            }
            .task { await categoriesVM.load() }
        }
    }

    private func beginEdit(_ cat: Category) {
        editingCategory = cat
    }

    /// Moves a category up or down within its group (top-level or within the same parent).
    /// `direction`: -1 = up, 1 = down.
    private func moveCategory(_ category: Category, direction: Int, isChild: Bool) {
        if isChild, let parentId = category.parentId {
            // Reorder among siblings of the same parent.
            var siblings = categoriesVM.childrenByParentId[parentId] ?? []
            guard let index = siblings.firstIndex(where: { $0.id == category.id }) else { return }
            let newIndex = index + direction
            guard newIndex >= 0 && newIndex < siblings.count else { return }
            siblings.swapAt(index, newIndex)
            Task {
                await categoriesVM.reorderChildCategories(parentId: parentId, to: siblings)
            }
        } else {
            // Reorder among top-level categories.
            var parents = categoriesVM.topLevelCategories
            guard let index = parents.firstIndex(where: { $0.id == category.id }) else { return }
            let newIndex = index + direction
            guard newIndex >= 0 && newIndex < parents.count else { return }
            parents.swapAt(index, newIndex)
            Task {
                await categoriesVM.reorderCategories(to: parents)
            }
        }
    }

    private func deleteCategory(_ category: Category) {
        var ids: Set<String> = [category.id]
        if let children = categoriesVM.childrenByParentId[category.id] {
            for child in children {
                ids.insert(child.id)
            }
        }
        pendingDeleteCategoryIds = Array(ids)
        showDeleteConfirmation = true
    }

    private func deleteCategories(at offsets: IndexSet) {
        let rows = categoryRows
        let baseIds = offsets.compactMap { index in
            rows.indices.contains(index) ? rows[index].category.id : nil
        }
        var allIds = Set(baseIds)
        // When deleting a parent, also delete its direct children.
        for id in baseIds {
            if let children = categoriesVM.childrenByParentId[id] {
                for child in children {
                    allIds.insert(child.id)
                }
            }
        }
        pendingDeleteCategoryIds = Array(allIds)
        showDeleteConfirmation = true
    }
}

private struct ReorderCategoriesSheet: View {
    let categoriesVM: CategoriesViewModel
    let onDismiss: () -> Void

    @State private var order: [Category] = []
    #if os(iOS)
    @State private var editMode: EditMode = .active
    #endif

    init(categoriesVM: CategoriesViewModel, onDismiss: @escaping () -> Void) {
        self.categoriesVM = categoriesVM
        self.onDismiss = onDismiss
        _order = State(initialValue: categoriesVM.topLevelCategories)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(order) { cat in
                    HStack(spacing: 12) {
                        if let hex = cat.color, let color = Color(hex: hex) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color)
                                .frame(width: 20, height: 20)
                        }
                        Text(cat.name)
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
                .onMove(perform: move)
            }
            #if os(iOS)
            .environment(\.editMode, $editMode)
            #endif
            .navigationTitle("Reorder categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .help("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            await categoriesVM.reorderCategories(to: order)
                        }
                        onDismiss()
                    }
                    .help("Save order")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func move(from source: IndexSet, to destination: Int) {
        var arr = order
        if let from = source.first {
            let item = arr.remove(at: from)
            var to = destination
            if from < destination { to -= 1 }
            arr.insert(item, at: to)
            order = arr
        }
    }
}

private struct EditCategorySheet: View {
    let category: Category
    let categoriesVM: CategoriesViewModel
    let onDismiss: () -> Void

    @State private var name: String
    @State private var selectedColor: String?
    @State private var selectedParentId: String

    init(category: Category, categoriesVM: CategoriesViewModel, onDismiss: @escaping () -> Void) {
        self.category = category
        self.categoriesVM = categoriesVM
        self.onDismiss = onDismiss
        _name = State(initialValue: category.name)
        _selectedColor = State(initialValue: category.color)
        _selectedParentId = State(initialValue: category.parentId ?? "")
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
                    Picker("Parent category", selection: $selectedParentId) {
                        Text("None").tag("")
                        ForEach(categoriesVM.validParents(forChildId: category.id)) { parent in
                            Text(parent.name).tag(parent.id)
                        }
                    }
                } header: {
                    Text("Parent")
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
                            let parentId = selectedParentId.isEmpty ? nil : selectedParentId
                            Task {
                                await categoriesVM.updateCategory(id: category.id, name: trimmed, color: selectedColor, parentId: parentId)
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

private struct NewCategorySheet: View {
    let categoriesVM: CategoriesViewModel
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var selectedParentId: String = ""

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
                    Picker("Parent category", selection: $selectedParentId) {
                        Text("None").tag("")
                        ForEach(categoriesVM.validParents()) { parent in
                            Text(parent.name).tag(parent.id)
                        }
                    }
                } header: {
                    Text("Parent")
                }
            }
            .formStyle(.grouped)
            .padding(24)
            .frame(width: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .navigationTitle("New category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .help("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let parentId = selectedParentId.isEmpty ? nil : selectedParentId
                        Task {
                            await categoriesVM.addCategory(name: trimmed, parentId: parentId)
                        }
                        onDismiss()
                    }
                    .help("Add category")
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
