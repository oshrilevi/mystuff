import SwiftUI
#if os(iOS)
import PhotosUI
import UIKit
#elseif os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct ItemFormView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss

    enum Mode: Equatable {
        case add(initialWebLink: String?, initialCategoryId: String?)
        case edit(Item)
    }
    let mode: Mode
    /// When set in edit mode, Save calls this with the updated item and does not dismiss (inline edit).
    var onSaveSuccess: ((Item) -> Void)? = nil
    /// When set in edit mode, Cancel calls this instead of dismissing (inline edit).
    var onCancel: (() -> Void)? = nil

    @State private var name = ""
    @State private var description = ""
    @State private var categoryId = ""
    @State private var price = ""
    @State private var purchaseDateValue: Date = Date()
    @State private var quantity = 1
    @State private var quantityText = "1"
    @State private var webLink = ""
    @State private var tagsText = "" // Comma-separated tags
    @State private var locationId = ""
    @State private var priceCurrency = "NIS"
    @State private var isExtracting = false
    #if os(iOS)
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var capturedImageData: Data?
    #elseif os(macOS)
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImageData: Data?
    #endif
    @State private var imageData: [Data] = []
    @State private var removedPhoto = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDatePicker = false
    @FocusState private var focusedField: FocusField?

    private enum FocusField {
        case absorbInitialFocus  // used in edit mode so name field never gets auto-focus (and thus no select-all)
        case url
    }

    private var inventory: InventoryViewModel { session.inventory }
    private var drive: DriveService { session.drive }
    private var pageMetadata: PageMetadataService { session.pageMetadata }
    private var categories: [Category] { session.categories.categories }
    private var sortedCategories: [Category] {
        categories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var locations: [Location] { session.locations.locations }
    private var sortedLocations: [Location] {
        locations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var isEdit: Bool { if case .edit = mode { true } else { false } }
    private var existingItem: Item? { if case .edit(let i) = mode { return i } else { return nil } }
    private var initialWebLinkForAdd: String? { if case .add(let url, _) = mode { return url } else { return nil } }
    private var initialCategoryIdForAdd: String? { if case .add(_, let cid) = mode { return cid } else { return nil } }
    private var isWishlistCategory: Bool {
        Category.isWishlist(categories.first(where: { $0.id == categoryId })?.name ?? "")
    }
    private var priceLabel: String {
        if isWishlistCategory { return "Price (\(priceCurrency))" }
        return "Price (NIS)"
    }

    private var showCurrentPhoto: Bool {
        isEdit && !removedPhoto && imageData.isEmpty && !(existingItem?.photoIds.first ?? "").isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // In edit mode, steal initial focus so the name field never gets auto-focused (avoids select-all).
                    if isEdit {
                        TextField("", text: .constant(""))
                            .frame(width: 1, height: 1)
                            .opacity(0)
                            .allowsHitTesting(false)
                            .focused($focusedField, equals: .absorbInitialFocus)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name").font(.subheadline).foregroundStyle(.secondary)
                        NameFieldCursorAtEnd(text: $name, placeholder: "Name")
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
                    if !isWishlistCategory {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Location").font(.subheadline).foregroundStyle(.secondary)
                            Picker("", selection: $locationId) {
                                Text("None").tag("")
                                ForEach(sortedLocations) { loc in
                                    Text(loc.name).tag(loc.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    if isWishlistCategory {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Currency").font(.subheadline).foregroundStyle(.secondary)
                            Picker("", selection: $priceCurrency) {
                                Text("NIS").tag("NIS")
                                Text("USD").tag("USD")
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(priceLabel).font(.subheadline).foregroundStyle(.secondary)
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
                    HStack(spacing: 12) {
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
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showCamera = true
                            } label: {
                                Label("Take photo", systemImage: "camera")
                            }
                        }
                    }
                    #elseif os(macOS)
                    HStack(spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera")
                        }
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
            .fullScreenCover(isPresented: $showCamera) {
                CameraImagePicker(capturedImageData: $capturedImageData) {
                    showCamera = false
                    if let data = capturedImageData {
                        imageData.append(data)
                        removedPhoto = false
                        selectedPhotos = []
                    }
                    capturedImageData = nil
                }
            }
            #elseif os(macOS)
            .sheet(isPresented: $showCamera) {
                MacCameraCaptureView(capturedImageData: $capturedImageData) {
                    showCamera = false
                    if let data = capturedImageData {
                        imageData.append(data)
                        removedPhoto = false
                    }
                    capturedImageData = nil
                }
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isEdit ? "Edit item" : "New item")
                        .font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let onCancel {
                            onCancel()
                        } else {
                            dismiss()
                        }
                    }
                    .help("Cancel")
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
                                .help("Save")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .defaultFocus($focusedField, isEdit ? .absorbInitialFocus : nil)
            .onAppear {
                fillForm()
                if isEdit {
                    // Steal initial focus so name field is never auto-focused (avoids select-all); then release.
                    focusedField = .absorbInitialFocus
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                        focusedField = nil
                    }
                } else {
                    categoryId = initialCategoryIdForAdd ?? inventory.lastNewItemCategoryId ?? inventory.selectedCategoryId ?? ""
                    locationId = inventory.lastNewItemLocationId ?? session.locations.defaultLocationId ?? ""
                    purchaseDateValue = inventory.lastNewItemPurchaseDate ?? Date()
                    if let url = initialWebLinkForAdd, !url.trimmingCharacters(in: .whitespaces).isEmpty {
                        webLink = url.trimmingCharacters(in: .whitespaces)
                        Task { await extractFromLink() }
                    } else {
                        pasteURLFromClipboardAndExtract()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            focusedField = .url
                        }
                    }
                }
            }
            .task {
                guard session.appState.spreadsheetId != nil, locations.isEmpty else { return }
                await session.locations.load()
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    private func pasteURLFromClipboardAndExtract() {
        let clipboardString: String? = {
            #if os(iOS)
            return UIPasteboard.general.string
            #elseif os(macOS)
            return NSPasteboard.general.string(forType: .string)
            #else
            return nil
            #endif
        }()
        guard let str = clipboardString?.trimmingCharacters(in: .whitespaces),
              !str.isEmpty,
              let url = URL(string: str),
              url.scheme == "https" || url.scheme == "http" else { return }
        webLink = str
        Task { await extractFromLink() }
    }

    private func fillForm() {
        if let item = existingItem {
            name = item.name
            description = item.description
            categoryId = item.categoryId
            price = item.price
            priceCurrency = item.priceCurrency.isEmpty ? "NIS" : item.priceCurrency
            purchaseDateValue = Self.dateFormatter.date(from: item.purchaseDate) ?? Date()
            quantity = item.quantity
            quantityText = "\(item.quantity)"
            webLink = item.webLink
            tagsText = item.tags.joined(separator: ", ")
            locationId = item.locationId
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
            if let resolved = metadata.resolvedURL?.absoluteString {
                webLink = resolved
            }
            if let t = metadata.title, !t.isEmpty { name = t }
            if let d = metadata.description, !d.isEmpty { description = d }
            if let p = metadata.price, !p.isEmpty { price = p }
            if !metadata.tags.isEmpty {
                tagsText = metadata.tags.joined(separator: ", ")
            }
        } catch {
            if case PageMetadataError.badStatus(let code) = error {
                if code == 403 {
                    errorMessage = "This site doesn't allow automatic fetching (HTTP 403). You can still add the item and fill in the name and details yourself."
                } else {
                    errorMessage = "Could not load details from this link (HTTP \(code)). You can still add the item and fill in the details yourself."
                }
            } else {
                errorMessage = error.localizedDescription
            }
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
        let resolvedPriceCurrency = isWishlistCategory ? priceCurrency : ""
        if isEdit, let existing = existingItem {
            var updated = existing
            updated.name = name.trimmingCharacters(in: .whitespaces)
            updated.description = description
            updated.categoryId = categoryId
            updated.price = price
            updated.priceCurrency = resolvedPriceCurrency
            updated.purchaseDate = purchaseDateString
            updated.condition = existing.condition
            updated.quantity = quantity
            updated.webLink = link
            updated.tags = tags
            updated.locationId = locationId
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
                tags: tags,
                locationId: locationId,
                priceCurrency: resolvedPriceCurrency
            )
            await inventory.addItem(newItem, imageData: imageData)
            if inventory.errorMessage == nil {
                inventory.lastNewItemPurchaseDate = purchaseDateValue
                inventory.lastNewItemCategoryId = categoryId
                inventory.lastNewItemLocationId = locationId
            }
        }
        if inventory.errorMessage == nil {
            if isEdit, let onSaveSuccess, let existing = existingItem {
                var updated = existing
                updated.name = name.trimmingCharacters(in: .whitespaces)
                updated.description = description
                updated.categoryId = categoryId
                updated.price = price
                updated.priceCurrency = resolvedPriceCurrency
                updated.purchaseDate = Self.dateFormatter.string(from: purchaseDateValue)
                updated.quantity = quantity
                updated.webLink = webLink.trimmingCharacters(in: .whitespaces)
                updated.tags = parsedTags()
                updated.locationId = locationId
                onSaveSuccess(updated)
            } else {
                dismiss()
            }
        } else {
            errorMessage = inventory.errorMessage
        }
    }
}

// MARK: - Name field that places cursor at end on focus (avoids full-text selection when opening edit)
#if os(iOS)
private struct NameFieldCursorAtEnd: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.text = text
        field.borderStyle = .roundedRect
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textChanged(_ field: UITextField) {
            text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            guard let t = textField.text, !t.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                let end = textField.endOfDocument
                textField.selectedTextRange = textField.textRange(from: end, to: end)
            }
        }
    }
}
#elseif os(macOS)
private struct NameFieldCursorAtEnd: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.stringValue = text
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.cell?.sendsActionOnEndEditing = false
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let s = field.stringValue
            guard !s.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                field.currentEditor()?.selectedRange = NSRange(location: s.utf16.count, length: 0)
            }
        }
    }
}
#endif
