import SwiftUI

struct CategoriesView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService
    @State private var newCategoryName = ""
    @State private var showAdd = false
    @State private var editingCategory: Category?
    @State private var editCategoryName = ""

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
                            Text(cat.name)
                                .contentShape(Rectangle())
                                .onTapGesture { beginEdit(cat) }
                                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
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
            .alert("Edit category", isPresented: Binding(get: { editingCategory != nil }, set: { if !$0 { editingCategory = nil } })) {
                TextField("Name", text: $editCategoryName)
                Button("Cancel", role: .cancel) { editingCategory = nil }
                Button("Save") {
                    if let cat = editingCategory, !editCategoryName.trimmingCharacters(in: .whitespaces).isEmpty {
                        Task { await categoriesVM.updateCategory(id: cat.id, name: editCategoryName.trimmingCharacters(in: .whitespaces)) }
                    }
                    editingCategory = nil
                }
            } message: {
                Text("Enter category name")
            }
            .task { await categoriesVM.load() }
        }
    }

    private func beginEdit(_ cat: Category) {
        editingCategory = cat
        editCategoryName = cat.name
    }

    private func deleteCategories(at offsets: IndexSet) {
        let ids = offsets.map { sortedCategories[$0].id }
        Task { await categoriesVM.deleteCategory(ids: ids) }
    }
}
