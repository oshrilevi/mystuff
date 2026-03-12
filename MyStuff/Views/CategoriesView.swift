import SwiftUI

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
    @State private var selectedParentId: String

    init(category: Category, categoriesVM: CategoriesViewModel, onDismiss: @escaping () -> Void) {
        self.category = category
        self.categoriesVM = categoriesVM
        self.onDismiss = onDismiss
        _name = State(initialValue: category.name)
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
                                await categoriesVM.updateCategory(id: category.id, name: trimmed, parentId: parentId)
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
