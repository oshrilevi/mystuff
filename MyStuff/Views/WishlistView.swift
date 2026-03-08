import SwiftUI
#if os(iOS)
import PhotosUI
import UIKit
#elseif os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct WishlistView: View {
    @EnvironmentObject var session: Session
    @State private var selectedItem: WishlistItem?
    @State private var showAddItem = false

    private var wishlist: WishlistViewModel { session.wishlist }

    var body: some View {
        NavigationStack {
            Group {
                if wishlist.isLoading, wishlist.items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let err = wishlist.errorMessage {
                            Section {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        if wishlist.filteredItems.isEmpty {
                            Section {
                                VStack(spacing: 12) {
                                    Image(systemName: "heart.slash")
                                        .font(.system(size: 44))
                                        .foregroundStyle(.secondary)
                                    Text(wishlist.searchText.isEmpty ? "No items in your wish list" : "No results for your search")
                                        .font(.headline)
                                        .multilineTextAlignment(.center)
                                    Text(wishlist.searchText.isEmpty ? "Tap + to add something you want to buy." : "Try a different search.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                    if wishlist.searchText.isEmpty {
                                        Button("Add item") { showAddItem = true }
                                            .buttonStyle(.borderedProminent)
                                            .padding(.top, 4)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 32)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } else {
                            ForEach(wishlist.filteredItems) { item in
                                WishlistRowView(item: item, drive: session.drive)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedItem = item }
                            }
                            .onDelete(perform: deleteItems)
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.inset)
                    #endif
                    .refreshable { await wishlist.load() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Wish list")
            .searchable(text: Binding(get: { wishlist.searchText }, set: { wishlist.searchText = $0 }), prompt: "Search wish list")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { showAddItem = true } label: { Image(systemName: "plus") }
                        UserAvatarMenuView()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        TextField("Search", text: Binding(get: { wishlist.searchText }, set: { wishlist.searchText = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 120, maxWidth: 200)
                        Button { showAddItem = true } label: { Image(systemName: "plus") }
                        UserAvatarMenuView()
                    }
                }
                #endif
            }
            .sheet(item: $selectedItem) { item in
                WishlistItemDetailView(item: item)
                    .environmentObject(session)
                    .onDisappear { Task { await wishlist.load() } }
            }
            .sheet(isPresented: $showAddItem) {
                WishlistItemFormView(mode: .add)
                    .environmentObject(session)
                    .onDisappear { Task { await wishlist.load() } }
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        let toDelete = offsets.map { wishlist.filteredItems[$0].id }
        Task { await wishlist.delete(ids: toDelete) }
    }
}

// MARK: - Form photo preview from Data

private struct WishlistFormPhotoPreview: View {
    let data: Data

    var body: some View {
        Group {
            #if os(iOS)
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            #elseif os(macOS)
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: 220)
        .clipped()
        .cornerRadius(8)
    }
}

// MARK: - Row

private struct WishlistRowView: View {
    let item: WishlistItem
    let drive: DriveService

    private let thumbSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 12) {
            if !item.photoId.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                    DriveImageView(drive: drive, fileId: item.photoId, contentMode: .fill)
                        .frame(width: thumbSize, height: thumbSize)
                        .clipped()
                        .cornerRadius(8)
                }
                .frame(width: thumbSize, height: thumbSize)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    if !item.price.isEmpty {
                        Text(WishlistItem.priceInNIS(item.price))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !item.link.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("Link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

struct WishlistItemDetailView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    let item: WishlistItem
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var isMoving = false

    private var wishlist: WishlistViewModel { session.wishlist }
    private var inventory: InventoryViewModel { session.inventory }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !item.photoId.isEmpty {
                        DriveImageView(drive: session.drive, fileId: item.photoId, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 280)
                            .clipped()
                            .cornerRadius(12)
                            .padding(.bottom, 8)
                    }
                    detailRow("Name", item.name)
                    if !item.notes.isEmpty {
                        detailRow("Notes", item.notes)
                    }
                    detailRow("Price", WishlistItem.priceInNIS(item.price))
                    if !item.link.isEmpty, let url = URL(string: item.link) {
                        Link("Open link", destination: url)
                            .font(.body)
                    }
                    Button {
                        Task { await moveToMyStuff() }
                    } label: {
                        Label("Move to my stuff", systemImage: "arrow.right.circle")
                    }
                    .disabled(isMoving)
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle(item.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showEdit = true }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                }
            }
            .sheet(isPresented: $showEdit) {
                WishlistItemFormView(mode: .edit(item))
                    .environmentObject(session)
                    .onDisappear {
                        Task { await wishlist.load() }
                        dismiss()
                    }
            }
            .alert("Delete item?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await wishlist.delete(ids: [item.id])
                        dismiss()
                    }
                }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }

    private func moveToMyStuff() async {
        isMoving = true
        defer { isMoving = false }
        let photoIds = item.photoId.isEmpty ? [] : [item.photoId]
        let newItem = Item(
            name: item.name,
            description: item.notes,
            categoryId: "",
            price: item.price,
            purchaseDate: ISO8601DateFormatter().string(from: Date()).prefix(10).description,
            condition: "",
            quantity: 1,
            photoIds: photoIds,
            webLink: item.link,
            tags: []
        )
        await inventory.addItem(newItem, imageData: [])
        if inventory.errorMessage == nil {
            await wishlist.delete(ids: [item.id])
            dismiss()
        }
    }
}

// MARK: - Form

struct WishlistItemFormView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss

    enum Mode {
        case add
        case edit(WishlistItem)
    }
    let mode: Mode

    @State private var name = ""
    @State private var notes = ""
    @State private var price = ""
    @State private var link = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isExtracting = false
    #if os(iOS)
    @State private var selectedPhoto: PhotosPickerItem?
    #elseif os(macOS)
    @State private var showImagePicker = false
    #endif
    @State private var imageData: Data?
    @State private var removePhoto = false
    @FocusState private var focusedField: FocusField?

    private enum FocusField {
        case link
    }

    private var wishlist: WishlistViewModel { session.wishlist }
    private var drive: DriveService { session.drive }
    private var pageMetadata: PageMetadataService { session.pageMetadata }
    private var isEdit: Bool { if case .edit = mode { true } else { false } }
    private var existingItem: WishlistItem? { if case .edit(let i) = mode { return i } else { return nil } }

    private var showExistingPhoto: Bool {
        isEdit && !removePhoto && imageData == nil && !(existingItem?.photoId.isEmpty ?? true)
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
                        Text("Notes").font(.subheadline).foregroundStyle(.secondary)
                        TextField("", text: $notes, prompt: Text("Notes"), axis: .vertical)
                            .lineLimit(3...6)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Price (NIS)").font(.subheadline).foregroundStyle(.secondary)
                        TextField("", text: $price, prompt: Text("Price"))
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Link").font(.subheadline).foregroundStyle(.secondary)
                        TextField("", text: $link, prompt: Text("https://…"))
                            .focused($focusedField, equals: .link)
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
                                ProgressView().scaleEffect(0.9)
                                Text("Extracting…")
                            }
                        } else {
                            Label("Extract from link", systemImage: "link.badge.plus")
                        }
                    }
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || isExtracting)
                }
                Section("Photo") {
                    if showExistingPhoto, let fileId = existingItem?.photoId {
                        VStack(alignment: .leading, spacing: 8) {
                            DriveImageView(drive: drive, fileId: fileId, contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: 220)
                                .clipped()
                                .cornerRadius(8)
                            HStack(spacing: 12) {
                                Button("Remove photo", role: .destructive) {
                                    removePhoto = true
                                    imageData = nil
                                    #if os(iOS)
                                    selectedPhoto = nil
                                    #endif
                                }
                            }
                        }
                    }
                    if let data = imageData {
                        VStack(alignment: .leading, spacing: 8) {
                            WishlistFormPhotoPreview(data: data)
                            Button("Remove photo", role: .destructive) {
                                imageData = nil
                                #if os(iOS)
                                selectedPhoto = nil
                                #endif
                            }
                        }
                    }
                    #if os(iOS)
                    if isEdit && showExistingPhoto {
                        Text("Or pick a new photo to replace:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    PhotosPicker(
                        selection: $selectedPhoto,
                        maxSelectionCount: 1,
                        matching: .images
                    ) {
                        Label(showExistingPhoto ? "Pick photo to replace" : "Pick photo", systemImage: "photo.on.rectangle.angled")
                    }
                    .onChange(of: selectedPhoto) { _, new in
                        removePhoto = false
                        Task { await loadPhoto(new) }
                    }
                    #elseif os(macOS)
                    if !showExistingPhoto || imageData != nil {
                        Button("Choose photo…") { showImagePicker = true }
                        .fileImporter(
                            isPresented: $showImagePicker,
                            allowedContentTypes: [.image, .jpeg, .png],
                            allowsMultipleSelection: false
                        ) { result in
                            guard case .success(let urls) = result, let url = urls.first else { return }
                            removePhoto = false
                            imageData = try? Data(contentsOf: url)
                        }
                    }
                    if imageData != nil {
                        Text("1 photo selected")
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
                    Text(isEdit ? "Edit wish" : "New wish")
                        .font(.headline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Group {
                        if isSaving {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.85)
                                Text("Saving…").font(.body)
                            }
                        } else {
                            Button("Save") { Task { await save() } }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { fillForm() }
            .task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                focusedField = .link
            }
        }
    }

    private func fillForm() {
        if let item = existingItem {
            name = item.name
            notes = item.notes
            price = item.price
            link = item.link
        }
    }

    private func extractFromLink() async {
        let urlString = link.trimmingCharacters(in: .whitespaces)
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
            if let d = metadata.description, !d.isEmpty { notes = d }
            if let p = metadata.price, !p.isEmpty { price = p }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if os(iOS)
    private func loadPhoto(_ item: PhotosPickerItem?) async {
        imageData = nil
        guard let item = item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            imageData = data
        }
    }
    #endif

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let linkTrimmed = link.trimmingCharacters(in: .whitespaces)
        if isEdit, let existing = existingItem {
            var updated = existing
            updated.name = name.trimmingCharacters(in: .whitespaces)
            updated.notes = notes
            updated.price = price
            updated.link = linkTrimmed
            await wishlist.update(updated, imageData: imageData, removePhoto: removePhoto)
        } else {
            let newItem = WishlistItem(
                name: name.trimmingCharacters(in: .whitespaces),
                notes: notes,
                price: price,
                link: linkTrimmed
            )
            await wishlist.add(newItem, imageData: imageData)
        }
        if wishlist.errorMessage == nil {
            dismiss()
        } else {
            errorMessage = wishlist.errorMessage
        }
    }
}
