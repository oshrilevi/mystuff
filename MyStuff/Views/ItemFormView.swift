import SwiftUI
#if os(iOS)
import PhotosUI
#elseif os(macOS)
import UniformTypeIdentifiers
#endif

struct ItemFormView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss

    enum Mode {
        case add
        case edit(Item)
    }
    let mode: Mode

    @State private var name = ""
    @State private var description = ""
    @State private var categoryId = ""
    @State private var price = ""
    @State private var purchaseDate = ""
    @State private var condition = ""
    #if os(iOS)
    @State private var selectedPhotos: [PhotosPickerItem] = []
    #elseif os(macOS)
    @State private var showImagePicker = false
    #endif
    @State private var imageData: [Data] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var inventory: InventoryViewModel { session.inventory }
    private var categories: [Category] { session.categories.categories }
    private var isEdit: Bool { if case .edit = mode { true } else { false } }
    private var existingItem: Item? { if case .edit(let i) = mode { return i } else { return nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Category", selection: $categoryId) {
                        Text("None").tag("")
                        ForEach(categories) { cat in
                            Text(cat.name).tag(cat.id)
                        }
                    }
                    TextField("Price", text: $price)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                    TextField("Purchase date (YYYY-MM-DD)", text: $purchaseDate)
                    Picker("Condition", selection: $condition) {
                        Text("").tag("")
                        ForEach(Item.conditionPresets, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Photos") {
                    #if os(iOS)
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 10,
                        matching: .images
                    ) {
                        Label("Pick photos", systemImage: "photo.on.rectangle.angled")
                    }
                    .onChange(of: selectedPhotos) { _, new in
                        Task { await loadPhotos(new) }
                    }
                    #elseif os(macOS)
                    Button("Choose images…") { showImagePicker = true }
                    .fileImporter(
                        isPresented: $showImagePicker,
                        allowedContentTypes: [.image, .jpeg, .png],
                        allowsMultipleSelection: true
                    ) { result in
                        guard case .success(let urls) = result else { return }
                        imageData = urls.compactMap { try? Data(contentsOf: $0) }
                    }
                    if !imageData.isEmpty {
                        Text("\(imageData.count) image(s) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    #endif
                }
                if let err = errorMessage {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle(isEdit ? "Edit item" : "New item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { fillForm() }
        }
    }

    private func fillForm() {
        if let item = existingItem {
            name = item.name
            description = item.description
            categoryId = item.categoryId
            price = item.price
            purchaseDate = item.purchaseDate
            condition = item.condition
        }
    }

    #if os(iOS)
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        imageData = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                imageData.append(data)
            }
        }
    }
    #endif

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        if isEdit, let existing = existingItem {
            var updated = existing
            updated.name = name.trimmingCharacters(in: .whitespaces)
            updated.description = description
            updated.categoryId = categoryId
            updated.price = price
            updated.purchaseDate = purchaseDate
            updated.condition = condition
            await inventory.updateItem(updated, newImageData: imageData)
        } else {
            let newItem = Item(
                name: name.trimmingCharacters(in: .whitespaces),
                description: description,
                categoryId: categoryId,
                price: price,
                purchaseDate: purchaseDate,
                condition: condition
            )
            await inventory.addItem(newItem, imageData: imageData)
        }
        if inventory.errorMessage == nil {
            dismiss()
        } else {
            errorMessage = inventory.errorMessage
        }
    }
}
