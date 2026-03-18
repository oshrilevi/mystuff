#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 13.0, *)
struct AmazonCSVImportView: View {
    @EnvironmentObject var session: Session
    @StateObject private var viewModel: AmazonCSVImportViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false

    private static let lastCSVPathKey = "mystuff_last_amazon_csv_path"
    private var hasRecentCSV: Bool {
        UserDefaults.standard.string(forKey: Self.lastCSVPathKey) != nil
    }

    init(inventoryViewModel: InventoryViewModel) {
        _viewModel = StateObject(wrappedValue: AmazonCSVImportViewModel(inventoryViewModel: inventoryViewModel))
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            filters
            content
            footer
        }
        .padding()
        .frame(minWidth: 900, minHeight: 500)
    }

    private var header: some View {
        HStack {
            Text("Import from Amazon CSV")
                .font(.title2.weight(.semibold))
            Spacer()
            Button("Load last CSV…") {
                guard let path = UserDefaults.standard.string(forKey: Self.lastCSVPathKey) else { return }
                let url = URL(fileURLWithPath: path)
                Task {
                    await viewModel.loadCSV(from: url)
                }
            }
            .disabled(!hasRecentCSV)
            Button("Choose CSV…") {
                showFileImporter = true
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .text, .data],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task {
                    await viewModel.loadCSV(from: url)
                }
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker("Year", selection: Binding(
                get: { viewModel.selectedYear ?? -1 },
                set: { newValue in
                    viewModel.selectedYear = newValue == -1 ? nil : newValue
                }
            )) {
                Text("All years").tag(-1)
                ForEach(viewModel.availableYears, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.menu)

            TextField("Search name or description", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)

            Spacer()
        }
    }

    private var content: some View {
        Group {
            if viewModel.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Parsing CSV…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredRows.isEmpty {
                Text("No items to show. Choose an Amazon Order History CSV to begin.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(viewModel.filteredRows) {
                    TableColumn("Thumbnail") { row in
                        if let url = row.thumbnailURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 48, height: 48)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 48)
                                        .clipped()
                                        .cornerRadius(6)
                                case .failure:
                                    Image(systemName: "photo")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 48, height: 48)
                                @unknown default:
                                    Image(systemName: "photo")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 48, height: 48)
                                }
                            }
                        } else {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 48, height: 48)
                        }
                    }
                    TableColumn("Import") { row in
                        Toggle(isOn: binding(for: row).isSelected) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                    TableColumn("Name") { row in
                        TextField("Name", text: binding(for: row).name)
                    }
                    TableColumn("Description") { row in
                        TextField("Description", text: binding(for: row).detailDescription)
                    }
                    TableColumn("Price") { row in
                        TextField("Price", text: binding(for: row).price)
                            .frame(maxWidth: 80)
                    }
                    TableColumn("Qty") { row in
                        Stepper(value: binding(for: row).quantity, in: 1...999) {
                            Text("\(binding(for: row).quantity.wrappedValue)")
                        }
                    }
                    TableColumn("Date") { row in
                        if let date = binding(for: row).purchaseDate.wrappedValue {
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { date },
                                    set: { newDate in
                                        binding(for: row).purchaseDate.wrappedValue = newDate
                                    }
                                ),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total: ₪\(viewModel.selectedTotal, specifier: "%.2f")")
                    .font(.subheadline.weight(.medium))
                if let message = viewModel.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            Button("Import selected") {
                Task {
                    await viewModel.importSelectedItems()
                    dismiss()
                }
            }
            .disabled(viewModel.rows.allSatisfy { !$0.isSelected })
        }
        .padding(.top, 8)
    }

    private func binding(for row: AmazonCSVImportViewModel.ImportedAmazonItemRow) -> Binding<AmazonCSVImportViewModel.ImportedAmazonItemRow> {
        guard let index = viewModel.rows.firstIndex(where: { $0.id == row.id }) else {
            fatalError("Row not found")
        }
        return $viewModel.rows[index]
    }
}

#endif

