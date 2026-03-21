import SwiftUI
import UniformTypeIdentifiers
import WebKit
#if os(macOS)
import AppKit
#endif

enum MainSidebarSelection: Hashable {
    case items
    case lists
    case combos
    case trips
    case tripLocations
    case categories
    case locations
    case storesList
    case store(UserStore)
    case sourcesList
    case source(UserSource)
    case youtube

    /// Stable string key for UserDefaults persistence. Empty for associated-value cases.
    var storageKey: String {
        switch self {
        case .items:         return "items"
        case .lists:         return "lists"
        case .combos:        return "combos"
        case .trips:         return "trips"
        case .tripLocations: return "tripLocations"
        case .categories:    return "categories"
        case .locations:     return "locations"
        case .storesList:    return "storesList"
        case .sourcesList:   return "sourcesList"
        case .youtube:       return "youtube"
        case .store, .source: return ""
        }
    }

    static func from(storageKey: String) -> MainSidebarSelection? {
        switch storageKey {
        case "items":         return .items
        case "lists":         return .lists
        case "combos":        return .combos
        case "trips":         return .trips
        case "tripLocations": return .tripLocations
        case "categories":    return .categories
        case "locations":     return .locations
        case "storesList":    return .storesList
        case "sourcesList":   return .sourcesList
        case "youtube":       return .youtube
        default:              return nil
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lastSidebarSelection") private var lastSidebarKey: String = "items"
    @AppStorage("itemViewMode") private var itemViewMode: ItemViewMode = .grid
    @State private var selection: MainSidebarSelection = .items
    #if os(macOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #endif
    var body: some View {
        #if os(iOS)
        TabView(selection: $selection) {
            ItemsTabView(viewMode: $itemViewMode)
                .tabItem { Label("Oshri's World", systemImage: "square.grid.2x2") }
                .tag(MainSidebarSelection.items)
            CategoriesView()
                .tabItem { Label("Categories", systemImage: "folder") }
                .tag(MainSidebarSelection.categories)
            LocationsView()
                .tabItem { Label("Locations", systemImage: "location") }
                .tag(MainSidebarSelection.locations)
            StoresTabContent()
                .tabItem { Label("Stores", systemImage: "cart") }
                .tag(MainSidebarSelection.storesList)
            TripsView()
                .tabItem { Label("Locations", systemImage: "map") }
                .tag(MainSidebarSelection.trips)
            SourcesTabContent()
                .tabItem { Label("Sources", systemImage: "link") }
                .tag(MainSidebarSelection.sourcesList)
            YouTubeSearchView()
                .tabItem {
                    Label {
                        Text("YouTube")
                    } icon: {
                        FaviconView(urlString: "https://www.youtube.com", fallbackSystemImage: "play.rectangle", size: 24)
                    }
                }
                .tag(MainSidebarSelection.youtube)
        }
        .onChange(of: session.requestedSidebarSelection) { _, newValue in
            if let sel = newValue {
                selection = sel
                session.requestedSidebarSelection = nil
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await session.prefetchWishlistPricesIfNeeded() }
            }
        }
        .onAppear {
            if let saved = MainSidebarSelection.from(storageKey: lastSidebarKey) {
                selection = saved
            }
        }
        .onChange(of: selection) { _, newVal in
            if !newVal.storageKey.isEmpty { lastSidebarKey = newVal.storageKey }
        }
        #else
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                NavigationLink(value: MainSidebarSelection.items) { Label("My Stuff", systemImage: "square.grid.2x2") }
                NavigationLink(value: MainSidebarSelection.combos) { Label("Combos", systemImage: "square.stack.3d.up") }
                NavigationLink(value: MainSidebarSelection.lists) { Label("My Lists", systemImage: "checklist") }
                NavigationLink(value: MainSidebarSelection.trips) { Label("Field Journal", systemImage: "binoculars") }
                Section("Media") {
                    NavigationLink(value: MainSidebarSelection.youtube) {
                        Label {
                            Text("YouTube")
                        } icon: {
                            FaviconView(urlString: "https://www.youtube.com", fallbackSystemImage: "play.rectangle", size: 20)
                        }
                    }
                }
                Section("Stores") {
                    ForEach(session.stores.stores.sorted(by: { $0.order < $1.order })) { store in
                        NavigationLink(value: MainSidebarSelection.store(store)) {
                            Label {
                                Text(store.name)
                            } icon: {
                                StoreIconView(store: store, size: 20)
                            }
                        }
                    }
                }
                Section("Sources") {
                    ForEach(session.sources.sources.sorted(by: { $0.order < $1.order })) { source in
                        NavigationLink(value: MainSidebarSelection.source(source)) {
                            Label {
                                Text(source.name)
                            } icon: {
                                SourceIconView(source: source, size: 20)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    SettingsMenuButton(selection: $selection)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selection {
                case .items:
                    ItemsTabView(viewMode: $itemViewMode)
                case .lists:
                    ListsView()
                case .trips:
                    TripsView()
                case .tripLocations:
                    TripLocationsManagementView()
                case .combos:
                    CombosView()
                case .categories:
                    CategoriesView()
                case .locations:
                    LocationsView()
                case .storesList:
                    StoresView()
                case .store(let store):
                    StoreBrowserView(store: store)
                        .id(store.id)
                case .sourcesList:
                    SourcesView()
                case .source(let source):
                    SourceBrowserView(source: source)
                        .id(source.id)
                case .youtube:
                    YouTubeSearchView()
                }
            }
            .onChange(of: session.requestedSidebarSelection) { _, newValue in
                if let sel = newValue {
                    selection = sel
                    session.requestedSidebarSelection = nil
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await session.prefetchWishlistPricesIfNeeded() }
            }
        }
        .onAppear {
            if let saved = MainSidebarSelection.from(storageKey: lastSidebarKey) {
                selection = saved
                columnVisibility = saved == .trips ? .detailOnly : .all
            }
        }
        .onChange(of: selection) { _, newVal in
            if !newVal.storageKey.isEmpty { lastSidebarKey = newVal.storageKey }
            columnVisibility = newVal == .trips ? .detailOnly : .all
        }
        #endif
    }
}

#if os(macOS)
private struct SettingsMenuButton: View {
    @Binding var selection: MainSidebarSelection
    @EnvironmentObject var session: Session
    @State private var isExportingPDF = false
    @State private var isExportingZIP = false
    @State private var isImportingAmazonCSV = false
    @State private var isExpanded = false
    @State private var hoveredRow: SettingsRow?

    private enum SettingsRow: Hashable {
        case categories
        case locations
        case tripLocations
        case stores
        case sources
        case exportCSV
        case exportPDF
        case exportZIP
        case importAmazonCSV
    }

    var body: some View {
        VStack(spacing: 12) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    settingsRowButton(
                        title: "Categories",
                        systemImage: "folder",
                        row: .categories
                    ) {
                        selection = .categories
                    }

                    settingsRowButton(
                        title: "Locations",
                        systemImage: "location",
                        row: .locations
                    ) {
                        selection = .locations
                    }

                    settingsRowButton(
                        title: "Trip Locations",
                        systemImage: "mappin.and.ellipse",
                        row: .tripLocations
                    ) {
                        selection = .tripLocations
                    }

                    settingsRowButton(
                        title: "Stores",
                        systemImage: "cart",
                        row: .stores
                    ) {
                        selection = .storesList
                    }

                    settingsRowButton(
                        title: "Sources",
                        systemImage: "link",
                        row: .sources
                    ) {
                        selection = .sourcesList
                    }

                    Divider()
                        .padding(.top, 4)

                    Text("Exports")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    settingsRowButton(
                        title: "Export as CSV",
                        systemImage: "table",
                        row: .exportCSV
                    ) {
                        exportCSV()
                    }

                    settingsRowButton(
                        title: "Export as PDF",
                        systemImage: "doc.richtext",
                        row: .exportPDF
                    ) {
                        isExportingPDF = true
                        Task {
                            await exportPDF()
                            await MainActor.run { isExportingPDF = false }
                        }
                    }

                    settingsRowButton(
                        title: "Export as ZIP",
                        systemImage: "archivebox",
                        row: .exportZIP
                    ) {
                        isExportingZIP = true
                        Task {
                            await exportZIP()
                            await MainActor.run { isExportingZIP = false }
                        }
                    }
                    
                    Divider()
                        .padding(.top, 4)

                    Text("Imports")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    settingsRowButton(
                        title: "From Amazon",
                        systemImage: "tray.and.arrow.down",
                        row: .importAmazonCSV
                    ) {
                        isImportingAmazonCSV = true
                    }

                    Divider()
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                Text("SETTINGS")
                    .font(.callout.weight(.semibold))
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .buttonStyle(.plain)
        .sheet(isPresented: $isExportingPDF) {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Generating PDF…")
                    .font(.headline)
            }
            .frame(width: 200, height: 100)
        }
        .sheet(isPresented: $isExportingZIP) {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Preparing ZIP export…")
                    .font(.headline)
            }
            .frame(width: 220, height: 100)
        }
        .sheet(isPresented: $isImportingAmazonCSV) {
            AmazonCSVImportView(inventoryViewModel: session.inventory)
                .environmentObject(session)
        }
    }

    private func settingsRowButton(
        title: String,
        systemImage: String,
        row: SettingsRow,
        action: @escaping () -> Void
    ) -> some View {
        let isSelected = isRowSelected(row)
        return Button {
            action()
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .frame(width: 16, alignment: .center)
                Text(title)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(highlightColor(for: row))
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredRow = hovering ? row : (hoveredRow == row ? nil : hoveredRow)
        }
    }

    private func highlightColor(for row: SettingsRow) -> Color {
        if isRowSelected(row) {
            return Color.accentColor.opacity(0.18)
        }
        if hoveredRow == row {
            return Color.accentColor.opacity(0.10)
        }
        return .clear
    }

    private func isRowSelected(_ row: SettingsRow) -> Bool {
        switch row {
        case .categories:
            return selection == .categories
        case .locations:
            return selection == .locations
        case .tripLocations:
            return selection == .tripLocations
        case .stores:
            return selection == .storesList
        case .sources:
            return selection == .sourcesList
        case .exportCSV, .exportPDF, .exportZIP, .importAmazonCSV:
            return false
        }
    }

    private func exportCSV() {
        let data = ExportService.makeCSVData(
            items: session.inventory.items,
            categories: session.categories.categories,
            locations: session.locations.locations
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mystuff_items.csv")
        try? data.write(to: tempURL)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "mystuff_items.csv"
        panel.begin { response in
            if response == .OK, let dest = panel.url {
                try? FileManager.default.copyItem(at: tempURL, to: dest)
            }
        }
    }

    private func exportPDF() async {
        let data = await ExportService.makePDFData(
            items: session.inventory.items,
            categories: session.categories.categories,
            locations: session.locations.locations,
            drive: session.drive
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mystuff_items.pdf")
        try? data.write(to: tempURL)
        await MainActor.run {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "mystuff_items.pdf"
            panel.begin { response in
                if response == .OK, let dest = panel.url {
                    try? FileManager.default.copyItem(at: tempURL, to: dest)
                }
            }
        }
    }

    private func exportZIP() async {
        do {
            let zipURL = try await ExportService.makeZIPArchiveURL(
                items: session.inventory.items,
                categories: session.categories.categories,
                locations: session.locations.locations,
                attachments: session.attachments.attachments,
                drive: session.drive
            )
            await MainActor.run {
                let fm = FileManager.default
                if let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                    let dest = downloads.appendingPathComponent("MyStuffBackup.zip")
                    // Overwrite any existing backup with the latest export.
                    try? fm.removeItem(at: dest)
                    do {
                        try fm.copyItem(at: zipURL, to: dest)
                        showBackupCompletedToast(destination: dest)
                    } catch {
                        // If copy fails, we silently ignore for now.
                    }
                }
            }
        } catch {
            // Ignore for now; progress sheet will dismiss.
        }
    }

    private func showBackupCompletedToast(destination: URL) {
        #if os(macOS)
        let notification = NSUserNotification()
        notification.title = "Oshri's World Backup Complete"
        notification.informativeText = "Saved to Downloads/\(destination.lastPathComponent)"
        NSUserNotificationCenter.default.deliver(notification)
        #endif
    }
}
#endif

#if os(macOS)
import AppKit

// In-app cache for Amazon product thumbnails so we don't refetch on every redraw.
/// Loads Amazon product pages in a hidden WKWebView to extract the real product image URL.
/// Requests are serialised — only one page loads at a time — to avoid hammering the network.
@MainActor
private final class AmazonWebViewScraper: NSObject, WKNavigationDelegate {
    static let shared = AmazonWebViewScraper()

    private let webView: WKWebView
    private var queue: [(URL, CheckedContinuation<URL?, Never>)] = []
    private var activeContinuation: CheckedContinuation<URL?, Never>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
    }

    func imageURL(for productURL: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            queue.append((productURL, continuation))
            if activeContinuation == nil { loadNext() }
        }
    }

    private func loadNext() {
        guard activeContinuation == nil, !queue.isEmpty else { return }
        let (url, continuation) = queue.removeFirst()
        activeContinuation = continuation
        webView.load(URLRequest(url: url))
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.webView.stopLoading()
            self.complete(with: nil)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            // Brief pause so synchronous page JS can run
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.extractAndComplete()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.complete(with: nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.complete(with: nil) }
    }

    private func extractAndComplete() async {
        guard activeContinuation != nil else { return }
        let js = """
        (function() {
            var og = document.querySelector('meta[property="og:image"]');
            if (og && og.content && og.content.length > 10) return og.content;
            var img = document.querySelector('#landingImage') || document.querySelector('#imgBlkFront');
            if (img) {
                var h = img.getAttribute('data-old-hires');
                if (h && h.length > 10) return h;
                if (img.src && img.src.indexOf('http') === 0) return img.src;
            }
            return null;
        })()
        """
        let result = await withCheckedContinuation { (cont: CheckedContinuation<Any?, Never>) in
            webView.evaluateJavaScript(js) { value, _ in cont.resume(returning: value) }
        }
        complete(with: (result as? String).flatMap { URL(string: $0) })
    }

    private func complete(with url: URL?) {
        guard activeContinuation != nil else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        activeContinuation?.resume(returning: url)
        activeContinuation = nil
        loadNext()
    }
}

private final class AmazonThumbnailCache {
    static let shared = AmazonThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

struct CachedURLThumbnailView: View {
    let urls: [URL]
    let size: CGFloat
    var asin: String = ""
    var website: String = "www.amazon.com"

    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var hasFailed = false

    private static var scrapeCache: [String: URL?] = [:]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.15))
                .frame(width: size, height: size)

            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
                    .cornerRadius(6)
            } else if isLoading {
                ProgressView()
                    .frame(width: size, height: size)
            } else if hasFailed {
                VStack(spacing: 2) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(.orange)
                    Text("No image")
                        .font(.system(size: size * 0.18))
                        .foregroundStyle(.secondary)
                }
                .frame(width: size, height: size)
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: urls) { _ in
            image = nil
            hasFailed = false
            loadIfNeeded()
        }
    }

    private static let thumbnailSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }()

    private func loadIfNeeded() {
        guard !urls.isEmpty || !asin.isEmpty else { return }
        if let cached = urls.lazy.compactMap({ AmazonThumbnailCache.shared.image(for: $0) }).first {
            image = cached
            return
        }
        isLoading = true
        Task {
            // Try CDN URLs first — fast, no scraping needed
            var img: NSImage? = await withTaskGroup(of: NSImage?.self) { group -> NSImage? in
                for url in urls {
                    group.addTask { await fetchImage(from: url) }
                }
                for await result in group {
                    if let img = result {
                        group.cancelAll()
                        return img
                    }
                }
                return nil
            }
            if let img {
                if let url = urls.first { AmazonThumbnailCache.shared.insert(img, for: url) }
            }

            // CDN failed — load the Amazon product page in a WKWebView and extract the image
            if img == nil, !asin.isEmpty {
                let host = website.isEmpty ? "www.amazon.com" : website
                let cacheKey = "\(host)|\(asin)"
                let scrapedURL: URL?
                if Self.scrapeCache.keys.contains(cacheKey) {
                    scrapedURL = Self.scrapeCache[cacheKey] ?? nil
                } else if let productURL = URL(string: "https://\(host)/dp/\(asin)") {
                    let result = await AmazonWebViewScraper.shared.imageURL(for: productURL)
                    Self.scrapeCache[cacheKey] = result
                    scrapedURL = result
                } else {
                    scrapedURL = nil
                }
                if let scrapedURL, let scrapedImg = await fetchImage(from: scrapedURL) {
                    img = scrapedImg
                    AmazonThumbnailCache.shared.insert(scrapedImg, for: scrapedURL)
                }
            }

            await MainActor.run {
                if let img {
                    image = img
                } else {
                    hasFailed = true
                }
                isLoading = false
            }
        }
    }

    private func fetchImage(from url: URL) async -> NSImage? {
        do {
            let (data, response) = try await Self.thumbnailSession.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let finalURL = response.url?.absoluteString ?? ""
            guard !finalURL.contains("no-img"), !finalURL.contains("no_img"), !finalURL.contains("no-image") else { return nil }
            guard let img = NSImage(data: data) else { return nil }
            let rep = img.representations.first
            guard (rep?.pixelsWide ?? 0) >= 50, (rep?.pixelsHigh ?? 0) >= 50 else { return nil }
            return img
        } catch {
            return nil
        }
    }
}

@MainActor
final class AmazonCSVImportViewModel: ObservableObject {
    private static let lastCSVPathKey = "mystuff_last_amazon_csv_path"
    struct ImportedAmazonItemRow: Identifiable {
        let id = UUID()
        var isSelected: Bool = false
        var isExisting: Bool = false

        // Raw reference data
        var asin: String
        var orderId: String
        var website: String

        /// Thumbnail URL derived from the ASIN for Amazon image preview in the import UI only.
        var thumbnailURL: URL?

        // User-editable fields
        var name: String
        var detailDescription: String
        var price: String
        var purchaseDate: Date?
        var categoryId: String?
        var locationId: String?
        var currency: String
    }

    @Published var rows: [ImportedAmazonItemRow] = []
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorMessage: String?
    @Published var exchangeRate: String = "3.3"
    @Published var lastSelectedCategoryId: String?

    // Filtering
    @Published var selectedYear: Int?
    @Published var searchText: String = ""
    @Published var hideAlreadyOwned: Bool = true

    private let inventoryViewModel: InventoryViewModel

    init(inventoryViewModel: InventoryViewModel) {
        self.inventoryViewModel = inventoryViewModel
    }

    var availableYears: [Int] {
        let years = rows.compactMap { row -> Int? in
            guard let date = row.purchaseDate else { return nil }
            return Calendar.current.component(.year, from: date)
        }
        return Array(Set(years)).sorted(by: >)
    }

    var filteredTotal: Double {
        filteredRows.reduce(0.0) { sum, row in
            let cleaned = row.price
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: "")
            let price = Double(cleaned) ?? 0
            return sum + price
        }
    }

    var filteredRows: [ImportedAmazonItemRow] {
        let base = rows.filter { row in
            // Hide already owned
            if hideAlreadyOwned && row.isExisting {
                return false
            }

            // Year filter
            if let year = selectedYear, let date = row.purchaseDate {
                let rowYear = Calendar.current.component(.year, from: date)
                if rowYear != year {
                    return false
                }
            }

            // Text filter
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                let q = query.lowercased()
                let matchesName = row.name.lowercased().contains(q)
                let matchesDescription = row.detailDescription.lowercased().contains(q)
                if !matchesName && !matchesDescription {
                    return false
                }
            }

            return true
        }

        return base.sorted { lhs, rhs in
            // Default sort: name ascending
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Build the list of `Item`s to import from the currently selected rows.
    /// Returns `nil` if validation fails (e.g. missing category), and an empty
    /// array if there are simply no selected rows.
    func validatedItemsToImport() -> [Item]? {
        let selected = rows.filter { $0.isSelected && !$0.isExisting }
        if selected.isEmpty {
            return []
        }

        // Validate categories
        let rowsNeedingCategory = selected.filter { row in
            (row.categoryId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !rowsNeedingCategory.isEmpty {
            errorMessage = "Please select a category for all selected items."
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let rate = parsedExchangeRate()

        let itemsToImport: [Item] = selected.map { row in
            var item = Item()
            item.name = row.name
            item.description = row.detailDescription
            item.categoryId = row.categoryId ?? ""
            item.locationId = row.locationId ?? ""

            let trimmedPrice = row.price.trimmingCharacters(in: .whitespaces)
            if let usd = parsedPrice(from: trimmedPrice) {
                let nis = usd * rate
                item.price = String(format: "%.2f", nis)
            } else {
                // If we cannot parse the price, keep the original string and still
                // treat it as NIS so the user can correct it later.
                item.price = trimmedPrice
            }

            if let date = row.purchaseDate {
                item.purchaseDate = dateFormatter.string(from: date)
            }
            item.condition = "New"
            item.quantity = 1
            // Once imported, prices are always stored in NIS for inventory items.
            item.priceCurrency = ""

            let trimmedASIN = row.asin.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedASIN.isEmpty {
                item.webLink = "https://www.amazon.com/gp/product/\(trimmedASIN)/"
            }

            return item
        }

        return itemsToImport
    }

    private func parsedExchangeRate() -> Double {
        let trimmed = exchangeRate.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed), value > 0 {
            return value
        }
        return 3.3
    }

    private func parsedPrice(from string: String) -> Double? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        // Allow prices with commas (e.g. "1,234.56") by normalizing before parsing.
        let normalized = trimmed.replacingOccurrences(of: ",", with: "")
        return Double(normalized)
    }

    func loadCSV(from url: URL) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                errorMessage = "Could not read CSV as UTF-8 text."
                return
            }

            let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            guard let headerLine = lines.first else {
                errorMessage = "CSV file is empty."
                return
            }

            let headerColumns = parseCSVRow(headerLine)
            let headerIndex: [String: Int] = Dictionary(uniqueKeysWithValues: headerColumns.enumerated().map { ($1, $0) })

            func value(_ key: String, in columns: [String]) -> String {
                guard let idx = headerIndex[key], idx < columns.count else { return "" }
                return columns[idx]
            }

            let isoFormatter = ISO8601DateFormatter()
            let ymdFormatter = DateFormatter()
            ymdFormatter.locale = Locale(identifier: "en_US_POSIX")
            ymdFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            ymdFormatter.dateFormat = "yyyy-MM-dd"

            var imported: [ImportedAmazonItemRow] = []
            for line in lines.dropFirst() {
                let columns = parseCSVRow(line)
                if columns.isEmpty {
                    continue
                }

                let productName = value("Product Name", in: columns)
                if productName.isEmpty {
                    continue
                }

                let unitPrice = value("Unit Price", in: columns)
                let currency = "USD"
                let orderDateString = value("Order Date", in: columns)
                let orderId = value("Order ID", in: columns)
                let asin = value("ASIN", in: columns)
                let website = value("Website", in: columns)

            let trimmedASIN = asin.trimmingCharacters(in: .whitespacesAndNewlines)
            let thumbnailURL: URL?
            if !trimmedASIN.isEmpty {
                thumbnailURL = URL(string: "https://images-na.ssl-images-amazon.com/images/P/\(trimmedASIN).jpg")
            } else {
                thumbnailURL = nil
            }

                let trimmedOrderDate = orderDateString.trimmingCharacters(in: .whitespacesAndNewlines)
                let purchaseDate: Date?
                if !trimmedOrderDate.isEmpty {
                    if let d = isoFormatter.date(from: trimmedOrderDate) {
                        purchaseDate = d
                    } else {
                        // Fallback for non-ISO Amazon formats, e.g. "YYYY-MM-DD …"
                        let prefix10 = String(trimmedOrderDate.prefix(10))
                        purchaseDate = ymdFormatter.date(from: prefix10)
                    }
                } else {
                    purchaseDate = nil
                }

                var row = ImportedAmazonItemRow(
                    asin: asin,
                    orderId: orderId,
                    website: website,
                    thumbnailURL: thumbnailURL,
                    name: productName,
                    detailDescription: productName,
                    price: unitPrice,
                    purchaseDate: purchaseDate,
                    categoryId: nil,
                    locationId: nil,
                    currency: currency
                )

                if let existing = findExistingItem(forASIN: asin) {
                    let storedCategoryId = existing.categoryId.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !storedCategoryId.isEmpty {
                        row.categoryId = storedCategoryId
                    }
                    let storedLocationId = existing.locationId.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !storedLocationId.isEmpty {
                        row.locationId = storedLocationId
                    }
                    row.isExisting = true
                }

                imported.append(row)
            }

            rows = imported
            // Remember this CSV for quick re-loading next time.
            UserDefaults.standard.set(url.path, forKey: Self.lastCSVPathKey)
            selectedYear = nil
            searchText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importSelectedItems() async {
        let selected = rows.filter { $0.isSelected && !$0.isExisting }
        guard !selected.isEmpty else { return }

        let rowsNeedingCategory = selected.filter {
            ($0.categoryId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !rowsNeedingCategory.isEmpty {
            errorMessage = "Please select a category for all selected items."
            return
        }

        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let rate = parsedExchangeRate()

        for row in selected {
            var item = Item()
            item.name = row.name
            item.description = row.detailDescription
            item.categoryId = row.categoryId ?? ""
            item.locationId = row.locationId ?? ""

            let trimmedPrice = row.price.trimmingCharacters(in: .whitespaces)
            if let usd = parsedPrice(from: trimmedPrice) {
                item.price = String(format: "%.2f", usd * rate)
            } else {
                item.price = trimmedPrice
            }

            if let date = row.purchaseDate {
                item.purchaseDate = dateFormatter.string(from: date)
            }
            item.condition = "New"
            item.quantity = 1
            item.priceCurrency = ""

            let trimmedASIN = row.asin.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedASIN.isEmpty {
                item.webLink = "https://www.amazon.com/gp/product/\(trimmedASIN)/"
            }

            var imageData: [Data] = []
            if !trimmedASIN.isEmpty {
                let cdnURLs = [
                    URL(string: "https://images-na.ssl-images-amazon.com/images/P/\(trimmedASIN).jpg"),
                    URL(string: "https://images.amazon.com/images/P/\(trimmedASIN).jpg"),
                ].compactMap { $0 }

                // Use cached image from preview UI if available
                var thumbnailImage: NSImage? = cdnURLs.lazy
                    .compactMap { AmazonThumbnailCache.shared.image(for: $0) }.first

                // Fall back to scraping the product page
                if thumbnailImage == nil {
                    let host = row.website.isEmpty ? "www.amazon.com" : row.website
                    if let productURL = URL(string: "https://\(host)/dp/\(trimmedASIN)"),
                       let scrapedURL = await AmazonWebViewScraper.shared.imageURL(for: productURL) {
                        thumbnailImage = AmazonThumbnailCache.shared.image(for: scrapedURL)
                        if thumbnailImage == nil,
                           let (data, response) = try? await URLSession.shared.data(from: scrapedURL),
                           (response as? HTTPURLResponse)?.statusCode == 200,
                           let img = NSImage(data: data),
                           (img.representations.first?.pixelsWide ?? 0) >= 50 {
                            thumbnailImage = img
                        }
                    }
                }

                if let img = thumbnailImage,
                   let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let rep = NSBitmapImageRep(cgImage: cgImage)
                    if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                        imageData = [jpeg]
                    }
                }
            }

            await inventoryViewModel.addItem(item, imageData: imageData)
        }
    }

    private func findExistingItem(forASIN asin: String) -> Item? {
        let trimmedASIN = asin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedASIN.isEmpty else { return nil }
        let loweredASIN = trimmedASIN.lowercased()

        func extractASIN(from link: String) -> String? {
            let lower = link.lowercased()
            let markers = ["/gp/product/", "/dp/"]
            for marker in markers {
                if let range = lower.range(of: marker) {
                    let start = range.upperBound
                    let remainder = lower[start...]
                    var asinChars: [Character] = []
                    for ch in remainder {
                        if ch.isLetter || ch.isNumber {
                            asinChars.append(ch)
                            if asinChars.count == 10 {
                                break
                            }
                        } else {
                            break
                        }
                    }
                    if asinChars.count == 10 {
                        return String(asinChars)
                    }
                }
            }
            return nil
        }

        return inventoryViewModel.items.first { item in
            guard let linkASIN = extractASIN(from: item.webLink) else { return false }
            return linkASIN.lowercased() == loweredASIN
        }
    }


    // Simple CSV parser that respects quoted fields.
    private func parseCSVRow(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()

        while let ch = iterator.next() {
            if ch == "\"" {
                if inQuotes {
                    if let next = iterator.next() {
                        if next == "\"" {
                            current.append("\"")
                        } else if next == "," {
                            inQuotes = false
                            result.append(current)
                            current = ""
                        } else {
                            inQuotes = false
                            current.append(next)
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if ch == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }
}

@available(macOS 13.0, *)
struct AmazonCSVImportView: View {
    @EnvironmentObject var session: Session
    @StateObject private var viewModel: AmazonCSVImportViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false
    @State private var isShowingConfirm = false
    @State private var pendingItems: [Item] = []

    private static let lastCSVPathKey = "mystuff_last_amazon_csv_path"
    private var hasRecentCSV: Bool {
        UserDefaults.standard.string(forKey: Self.lastCSVPathKey) != nil
    }

    // Category hierarchy for the Category picker (matches ItemFormView behavior).
    private var categories: [Category] { session.categories.categories }
    private var wishlistCategoryId: String? {
        categories.first(where: { Category.isWishlist($0.name) })?.id
    }
    private var topLevelCategories: [Category] {
        categories
            .filter { ($0.parentId ?? "").isEmpty }
            .sorted { ($0.order, $0.name.lowercased()) < ($1.order, $1.name.lowercased()) }
    }
    private var childrenByParentId: [String: [Category]] {
        var result: [String: [Category]] = [:]
        for cat in categories {
            guard let pid = cat.parentId, !pid.isEmpty else { continue }
            result[pid, default: []].append(cat)
        }
        for (pid, list) in result {
            result[pid] = list.sorted { ($0.order, $0.name.lowercased()) < ($1.order, $1.name.lowercased()) }
        }
        return result
    }
    private struct CategoryPickerRow: Identifiable {
        let id: String
        let category: Category
        let isChild: Bool
        let indentLevel: Int
        let isSelectable: Bool
    }
    private var categoryPickerRows: [CategoryPickerRow] {
        var rows: [CategoryPickerRow] = []
        for parent in topLevelCategories {
            let children = childrenByParentId[parent.id] ?? []
            let isWishlist = wishlistCategoryId == parent.id

            if children.isEmpty {
                rows.append(
                    CategoryPickerRow(
                        id: parent.id,
                        category: parent,
                        isChild: false,
                        indentLevel: 0,
                        isSelectable: isWishlist
                    )
                )
            } else {
                rows.append(
                    CategoryPickerRow(
                        id: parent.id,
                        category: parent,
                        isChild: false,
                        indentLevel: 0,
                        isSelectable: isWishlist
                    )
                )
                for child in children {
                    rows.append(
                        CategoryPickerRow(
                            id: child.id,
                            category: child,
                            isChild: true,
                            indentLevel: 1,
                            isSelectable: true
                        )
                    )
                }
            }
        }
        return rows
    }

    // Default "Home" location for imported rows.
    private var homeLocationId: String? {
        session.locations.locations.first { $0.name == "Home" }?.id
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
        .frame(minWidth: 1200, minHeight: 700)
        .task {
            guard let path = UserDefaults.standard.string(forKey: Self.lastCSVPathKey) else { return }
            await viewModel.loadCSV(from: URL(fileURLWithPath: path))
        }
        .sheet(isPresented: $isShowingConfirm) {
            AmazonImportConfirmationView(
                items: pendingItems,
                categories: session.categories.categories,
                locations: session.locations.locations,
                exchangeRate: $viewModel.exchangeRate,
                isImporting: viewModel.isImporting,
                onConfirm: {
                    Task {
                        await viewModel.importSelectedItems()
                        isShowingConfirm = false
                        dismiss()
                    }
                },
                onCancel: {
                    isShowingConfirm = false
                }
            )
        }
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

    private var yearPicker: some View {
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
    }

    private var filters: some View {
        HStack(spacing: 12) {
            yearPicker
            TextField("Search name or description", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
            Toggle("Hide already owned", isOn: $viewModel.hideAlreadyOwned)
                .toggleStyle(.checkbox)
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
                    TableColumn("Import") { row in
                        if !row.isExisting {
                            Toggle(isOn: Binding(
                                get: { binding(for: row).isSelected.wrappedValue },
                                set: { newValue in
                                    binding(for: row).isSelected.wrappedValue = newValue
                                    if newValue,
                                       (binding(for: row).categoryId.wrappedValue ?? "").isEmpty,
                                       let lastCat = viewModel.lastSelectedCategoryId {
                                        binding(for: row).categoryId.wrappedValue = lastCat
                                    }
                                }
                            )) {
                                EmptyView()
                            }
                            .labelsHidden()
                        }
                    }
                    .width(50)

                    TableColumn("Thumbnail") { row in
                        CachedURLThumbnailView(urls: thumbnailURLs(for: row), size: 48, asin: row.asin, website: row.website)
                    }
                    .width(60)

                    TableColumn("Name") { row in
                        if row.isExisting {
                            Text(row.name)
                                .foregroundColor(.green)
                        } else {
                            TextField("Name", text: binding(for: row).name)
                        }
                    }
                    .width(min: 160, ideal: 260)

                    TableColumn("Description") { row in
                        if row.isExisting {
                            Text(row.detailDescription)
                                .foregroundColor(.green)
                        } else {
                            TextField("Description", text: binding(for: row).detailDescription)
                        }
                    }
                    .width(min: 220, ideal: 400)

                    TableColumn("Price") { row in
                        if row.isExisting {
                            Text(row.price)
                                .foregroundColor(.green)
                        } else {
                            TextField("Price", text: binding(for: row).price)
                                .frame(maxWidth: 80)
                        }
                    }
                    .width(80)

                    TableColumn("Category") { row in
                        if row.isExisting {
                            Text(categoryName(for: row.categoryId ?? ""))
                                .foregroundColor(.green)
                        } else {
                            Picker("Category", selection: Binding(
                                get: { binding(for: row).categoryId.wrappedValue ?? "" },
                                set: { newValue in
                                    let resolved = newValue.isEmpty ? nil : newValue
                                    binding(for: row).categoryId.wrappedValue = resolved
                                    viewModel.lastSelectedCategoryId = resolved
                                }
                            )) {
                                Text("—").tag("")
                                ForEach(categoryPickerRows) { pickerRow in
                                    let label = pickerRow.indentLevel == 0
                                        ? pickerRow.category.name
                                        : String(repeating: "    ", count: pickerRow.indentLevel) + pickerRow.category.name
                                    if pickerRow.isSelectable {
                                        Text(label).tag(pickerRow.category.id)
                                    } else {
                                        Text(label)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .disabled(true)
                                    }
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .width(140)

                    TableColumn("Location") { row in
                        if row.isExisting {
                            Text(locationName(for: row.locationId ?? ""))
                                .foregroundColor(.green)
                        } else {
                            Picker("Location", selection: Binding(
                                get: { binding(for: row).locationId.wrappedValue ?? "" },
                                set: { newValue in
                                    binding(for: row).locationId.wrappedValue = newValue.isEmpty ? nil : newValue
                                }
                            )) {
                                Text("—").tag("")
                                ForEach(session.locations.locations, id: \.id) { location in
                                    Text(location.name).tag(location.id)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .width(140)

                    TableColumn("Date") { row in
                        if let date = binding(for: row).purchaseDate.wrappedValue {
                            if row.isExisting {
                                Text(date, style: .date)
                                    .foregroundColor(.green)
                            } else {
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
                            }
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(140)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func categoryName(for id: String) -> String {
        session.categories.categories.first(where: { $0.id == id })?.name ?? "—"
    }

    private func locationName(for id: String) -> String {
        session.locations.locations.first(where: { $0.id == id })?.name ?? "—"
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total: $\(viewModel.filteredTotal, specifier: "%.2f")")
                    .font(.subheadline.weight(.medium))
                if let message = viewModel.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            let selectedCount = viewModel.rows.filter { $0.isSelected }.count
            Text("\(selectedCount) selected")
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Button("Cancel") {
                dismiss()
            }
            Button("Import selected") {
                guard let items = viewModel.validatedItemsToImport(), !items.isEmpty else {
                    return
                }
                pendingItems = items
                isShowingConfirm = true
            }
            .disabled(viewModel.rows.allSatisfy { !$0.isSelected })
        }
        .padding(.top, 8)
    }

    private func thumbnailURLs(for row: AmazonCSVImportViewModel.ImportedAmazonItemRow) -> [URL] {
        let asin = row.asin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asin.isEmpty else { return [] }
        return [
            URL(string: "https://images-na.ssl-images-amazon.com/images/P/\(asin).jpg"),
            URL(string: "https://images.amazon.com/images/P/\(asin).jpg"),
            URL(string: "https://images-na.ssl-images-amazon.com/images/P/\(asin).png"),
            URL(string: "https://images.amazon.com/images/P/\(asin).png")
        ].compactMap { $0 }
    }

    private func binding(for row: AmazonCSVImportViewModel.ImportedAmazonItemRow) -> Binding<AmazonCSVImportViewModel.ImportedAmazonItemRow> {
        guard let index = viewModel.rows.firstIndex(where: { $0.id == row.id }) else {
            fatalError("Row not found")
        }
        if viewModel.rows[index].locationId == nil, let homeId = homeLocationId {
            viewModel.rows[index].locationId = homeId
        }
        return $viewModel.rows[index]
    }
}

@available(macOS 13.0, *)
private struct AmazonImportConfirmationView: View {
    let items: [Item]
    let categories: [Category]
    let locations: [Location]
    @Binding var exchangeRate: String
    var isImporting: Bool
    var onConfirm: () -> Void
    var onCancel: () -> Void

    private func categoryName(for id: String) -> String {
        categories.first(where: { $0.id == id })?.name ?? "—"
    }

    private func locationName(for id: String) -> String {
        locations.first(where: { $0.id == id })?.name ?? "—"
    }

    private func displayDate(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Confirm import from Amazon")
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            Text("These \(items.count) item(s) will be added to MyStuff. Review the details below, then confirm or cancel.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text("Exchange rate (USD → NIS)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("", text: $exchangeRate)
                    .frame(width: 80)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Table(items) {
                TableColumn("Name") { item in
                    Text(item.name)
                }
                TableColumn("Description") { item in
                    Text(item.description)
                }
                TableColumn("Price (NIS)") { item in
                    Text(item.price)
                }
                TableColumn("Qty") { item in
                    Text("\(item.quantity)")
                }
                TableColumn("Purchase Date") { item in
                    Text(displayDate(item.purchaseDate))
                }
                TableColumn("Category") { item in
                    Text(categoryName(for: item.categoryId))
                }
                TableColumn("Location") { item in
                    Text(locationName(for: item.locationId))
                }
                TableColumn("Web Link") { item in
                    Text(item.webLink.isEmpty ? "—" : item.webLink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .disabled(isImporting)
                Button("Import \(items.count) item(s)") {
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isImporting)
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(minWidth: 1000, minHeight: 500)
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Importing…")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}
#endif

#if os(iOS)
/// On iOS, a single "Stores" tab that lists stores and pushes to the browser when one is tapped.
private struct StoresTabContent: View {
    @EnvironmentObject var session: Session

    private var sortedStores: [UserStore] {
        session.stores.stores.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedStores) { store in
                    NavigationLink(value: store) {
                        Label {
                            Text(store.name)
                        } icon: {
                            StoreIconView(store: store, size: 20)
                        }
                    }
                }
            }
            .navigationTitle("Stores")
            .navigationDestination(for: UserStore.self) { store in
                StoreBrowserView(store: store)
                    .id(store.id)
            }
        }
    }
}

/// On iOS, a single "Sources" tab that lists sources and pushes to the browser when one is tapped.
private struct SourcesTabContent: View {
    @EnvironmentObject var session: Session

    private var sortedSources: [UserSource] {
        session.sources.sources.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedSources) { source in
                    NavigationLink(value: source) {
                        Label {
                            Text(source.name)
                        } icon: {
                            SourceIconView(source: source, size: 20)
                        }
                    }
                }
            }
            .navigationTitle("Sources")
            .navigationDestination(for: UserSource.self) { source in
                SourceBrowserView(source: source)
                    .id(source.id)
            }
        }
    }
}
#endif

struct ItemsTabView: View {
    @EnvironmentObject var session: Session
    @Binding var viewMode: ItemViewMode

    var body: some View {
        Group {
            if viewMode == .graph {
                NodeGraphView(viewMode: $viewMode)
            } else if viewMode == .grid {
                GalleryView(viewMode: $viewMode)
            } else {
                ItemsListView(viewMode: $viewMode)
            }
        }
        .task {
            // Ensure combos are available from app launch so item context menus
            // can show which combos an item belongs to without first visiting Combos.
            await session.combos.ensureLoaded()
            await session.prefetchWishlistPricesIfNeeded()
        }
    }
}
