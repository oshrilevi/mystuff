import SwiftUI

struct CategoriesView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService
    @State private var newCategoryName = ""
    @State private var showAdd = false

    private var categoriesVM: CategoriesViewModel { session.categories }

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
                        ForEach(categoriesVM.categories) { cat in
                            Text(cat.name)
                        }
                        .onDelete(perform: deleteCategories)
                    }
                    .refreshable { await categoriesVM.load() }
                }
            }
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out") { authService.signOut() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
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
            .task { await categoriesVM.load() }
        }
    }

    private func deleteCategories(at offsets: IndexSet) {
        Task { await categoriesVM.deleteCategory(at: offsets) }
    }
}
