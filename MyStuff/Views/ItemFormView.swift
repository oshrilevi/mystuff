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
    @State private var purchaseDateValue: Date = Date()
    @State private var quantity = 1
    @State private var quantityText = "1"
    @State private var webLink = ""
    @State private var tagsText = "" // Comma-separated tags
    @State private var isExtracting = false
    #if os(iOS)
    @State private var selectedPhotos: [PhotosPickerItem] = []
    #elseif os(macOS)
    @State private var showImagePicker = false
    #endif
    @State private var imageData: [Data] = []
    @State private var removedPhoto = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDatePicker = false
    @FocusState private var focusedField: FocusField?

    private enum FocusField {
        case url
    }

    private var inventory: InventoryViewModel { session.inventory }
    private var drive: DriveService { session.drive }
    private var pageMetadata: PageMetadataService { session.pageMetadata }
    private var categories: [Category] { session.categories.categories }
    private var sortedCategories: [Category] {
        categories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var isEdit: Bool { if case .edit = mode { true } else { false } }
    private var existingItem: Item? { if case .edit(let i) = mode { return i } else { return nil } }
    private var isWishlistCategory: Bool {
        Category.isWishlist(categories.first(where: { $0.id == categoryId })?.name ?? "")
    }

    private var showCurrentPhoto: Bool {
        isEdit && !removedPhoto && imageData.isEmpty && !(existingItem?.photoIds.first ?? "").isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name").font(.subheadline).foregroundStyle(.secondary)
                        TextField("", text: $name, prompt: Text("Name"))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description").font(.subheadline).foregroundStyle(.secondary)
                        TextField("", text: $description, prompt: Text("Description"), axis: .vertical)
                            .lineLimit(3...6)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category").font(.subheadline).foregroundStyle(.secondary)
                        Picker("", selection: $categoryId) {
                            Text("None").tag("")
                            ForEach(sortedCategories) { cat in
                                Text(cat.name).tag(cat.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Price (NIS)").font(.subheadline).foregroundStyle(.secondary)
                        TextField("", text: $price, prompt: Text("Price"))
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    if !isWishlistCategory {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Purchase Date").font(.subheadline).foregroundStyle(.secondary)
                            Button {
                                showDatePicker = true
                            } label: {
                                HStack {
                                    Text(Self.dateFormatter.string(from: purchaseDateValue))
                                    Spacer()
                                    Image(systemName: "calendar")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .sheet(isPresented: $showDatePicker) {
                                NavigationStack {
                                    DatePicker("", selection: $purchaseDateValue, displayedComponents: .date)
                                        #if os(iOS)
                                        .datePickerStyle(.graphical)
                                        #endif
                                        .padding()
                                        .onChange(of: purchaseDateValue) { _, _ in
                                            showDatePicker = false
                                        }
                                        .toolbar {
                                            ToolbarItem(placement: .confirmationAction) {
                                                Button("Done") { showDatePicker = false }
                                            }
                                        }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Quantity").font(.subheadline).foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                TextField("", text: $quantityText, prompt: Text("1"))
                                    .onChange(of: quantityText) { _, new in
                                        let parsed = Int(new.filter { $0.isNumber }) ?? 0
                                        quantity = min(999, max(1, parsed))
                                        if parsed != quantity {
                                            quantityText = "\(quantity)"
                                        }
                                    }
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    #endif
                                HStack(spacing: 4) {
                                    Button {
                                        let next = min(999, quantity + 1)
                                        quantity = next
                                        quantityText = "\(next)"
                                    } label: {
                                        Image(systemName: "chevron.up")
                                            .font(.body.weight(.semibold))
                                            .frame(minWidth: 36, minHeight: 36)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        let next = max(1, quantity - 1)
                                        quantity = next
                                        quantityText = "\(next)"
                                    } label: {
                                        Image(systemName: "chevron.down")
                                            .font(.body.weight(.semibold))
                                            .frame(minWidth: 36, minHeight: 36)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Web link") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("URL").font(.subheadline).foregroundStyle(.secondary)
                        TextField("", text: $webLink, prompt: Text("https://…"))
                            .focused($focusedField, equals: .url)
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                    }
                    Button {
                        Task { await extractFromLink() }
                    } label: {
                        if isExtracting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.9)
                                Text("Extracting…")
                            }
                        } else {
                            Label("Extract from link", systemImage: "link.badge.plus")
                        }
                    }
                    .disabled(webLink.trimmingCharacters(in: .whitespaces).isEmpty || isExtracting)
                }
                Section("Tags") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags (comma-separated)").font(.subheadline).foregroundStyle(.secondary)
                        TextField("", text: $tagsText, prompt: Text("e.g. Nikon, camera, lens"))
                            .lineLimit(1...3)
                    }
                }
                Section("Photos") {
                    if showCurrentPhoto, let fileId = existingItem?.photoIds.first {
                        VStack(alignment: .leading, spacing: 8) {
                            DriveImageView(drive: drive, fileId: fileId, contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: 220)
                                .clipped()
                                .cornerRadius(8)
                            HStack(spacing: 12) {
                                Button("Remove photo") {
                                    removedPhoto = true
                                    imageData = []
                                    #if os(iOS)
                                    selectedPhotos = []
                                    #endif
                                }
                                .foregroundStyle(.red)
                                Button("Replace photo") {
                                    removedPhoto = false
                                    #if os(iOS)
                                    // Picker is below; user selects and we set imageData
                                    #elseif os(macOS)
                                    showImagePicker = true
                                    #endif
                                }
                            }
                        }
                    }
                    #if os(iOS)
                    if isEdit && showCurrentPhoto {
                        Text("Or pick new photos to replace:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 10,
                        matching: .images
                    ) {
                        Label(isEdit && showCurrentPhoto ? "Pick new photos to replace" : "Pick photos", systemImage: "photo.on.rectangle.angled")
                    }
                    .onChange(of: selectedPhotos) { _, new in
                        removedPhoto = false
                        Task { await loadPhotos(new) }
                    }
                    #elseif os(macOS)
                    if !showCurrentPhoto || !imageData.isEmpty {
                        Button("Choose images…") { showImagePicker = true }
                        .fileImporter(
                            isPresented: $showImagePicker,
                            allowedContentTypes: [.image, .jpeg, .png],
                            allowsMultipleSelection: true
                        ) { result in
                            guard case .success(let urls) = result else { return }
                            removedPhoto = false
                            imageData = urls.compactMap { try? Data(contentsOf: $0) }
                        }
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
            .padding(20)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isEdit ? "Edit item" : "New item")
                        .font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Group {
                        if isSaving {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.85)
                                Text("Saving…")
                                    .font(.body)
                            }
                        } else {
                            Button("Save") { Task { await save() } }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                fillForm()
                if !isEdit {
                    categoryId = inventory.lastNewItemCategoryId ?? inventory.selectedCategoryId ?? ""
                    purchaseDateValue = inventory.lastNewItemPurchaseDate ?? Date()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        focusedField = .url
                    }
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    private func fillForm() {
        if let item = existingItem {
            name = item.name
            description = item.description
            categoryId = item.categoryId
            price = item.price
            purchaseDateValue = Self.dateFormatter.date(from: item.purchaseDate) ?? Date()
            quantity = item.quantity
            quantityText = "\(item.quantity)"
            webLink = item.webLink
            tagsText = item.tags.joined(separator: ", ")
        }
    }

    private func parsedTags() -> [String] {
        tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func extractFromLink() async {
        let urlString = webLink.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: urlString), url.scheme == "https" || url.scheme == "http" else {
            errorMessage = "Please enter a valid HTTP or HTTPS URL."
            return
        }
        isExtracting = true
        errorMessage = nil
        defer { isExtracting = false }
        do {
            let metadata = try await pageMetadata.fetchMetadata(from: url)
            if let t = metadata.title, !t.isEmpty { name = t }
            if let d = metadata.description, !d.isEmpty { description = d }
            if let p = metadata.price, !p.isEmpty { price = p }
            if !metadata.tags.isEmpty {
                tagsText = metadata.tags.joined(separator: ", ")
            }
        } catch {
            errorMessage = error.localizedDescription
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
        let link = webLink.trimmingCharacters(in: .whitespaces)
        let purchaseDateString = Self.dateFormatter.string(from: purchaseDateValue)
        let tags = parsedTags()
        if isEdit, let existing = existingItem {
            var updated = existing
            updated.name = name.trimmingCharacters(in: .whitespaces)
            updated.description = description
            updated.categoryId = categoryId
            updated.price = price
            updated.purchaseDate = purchaseDateString
            updated.condition = existing.condition
            updated.quantity = quantity
            updated.webLink = link
            updated.tags = tags
            let replacePhotos = removedPhoto || !imageData.isEmpty
            await inventory.updateItem(updated, newImageData: imageData, replaceExistingPhotos: replacePhotos)
        } else {
            let newItem = Item(
                name: name.trimmingCharacters(in: .whitespaces),
                description: description,
                categoryId: categoryId,
                price: price,
                purchaseDate: purchaseDateString,
                condition: "",
                quantity: quantity,
                webLink: link,
                tags: tags
            )
            await inventory.addItem(newItem, imageData: imageData)
            if inventory.errorMessage == nil {
                inventory.lastNewItemPurchaseDate = purchaseDateValue
                inventory.lastNewItemCategoryId = categoryId
            }
        }
        if inventory.errorMessage == nil {
            dismiss()
        } else {
            errorMessage = inventory.errorMessage
        }
    }
}
