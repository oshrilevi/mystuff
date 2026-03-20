import Foundation
import SwiftUI
import GoogleSignIn
import Combine

@MainActor
final class Session: ObservableObject {
    /// When set, MainTabView should switch to this selection (e.g. from ItemDetailView "Search on YouTube").
    @Published var requestedSidebarSelection: MainSidebarSelection?
    /// Optional search query for the YouTube section; consumed by YouTubeSearchView on appear.
    @Published var youtubeSearchQuery: String?
    /// Optional search query for the Amazon store; consumed by StoreBrowserView when opening the Amazon store.
    @Published var amazonSearchQuery: String?
    /// Optional combo id to focus when navigating to the Combos view (e.g. from an item context menu).
    @Published var requestedComboFocusId: String?

    /// Cache of current store prices keyed by product URL (absolute string). Filled on app load for wishlist items and when opening item detail.
    @Published var storePriceCache: [String: String] = [:]
    /// URL keys currently being fetched (so list/grid can show loading).
    @Published var storePriceFetching: Set<String> = []
    /// URL keys we tried and failed to get a price (so list/grid show red dash only then).
    @Published var storePriceFailed: Set<String> = []

    let appState: AppState
    let sheets: SheetsService
    let drive: DriveService
    let pageMetadata: PageMetadataService
    let browserPrice: BrowserPriceService
    let inventory: InventoryViewModel
    let categories: CategoriesViewModel
    let locations: LocationsViewModel
    let stores: StoresViewModel
    let sources: SourcesViewModel
    let attachments: AttachmentsViewModel
    let lists: ListsViewModel
    let combos: CombosViewModel
    let trips: TripsViewModel

    private let authService: GoogleAuthService
    private var cancellables = Set<AnyCancellable>()

    private static let lastPrefetchDateKey = "mystuff_wishlist_price_last_prefetch_date"
    private var isPrefetchingWishlistPrices = false

    init(authService: GoogleAuthService) {
        self.authService = authService
        self.appState = AppState()
        self.sheets = SheetsService(tokenProvider: { [weak authService] in
            try await authService?.getAccessToken() ?? ""
        })
        self.drive = DriveService(tokenProvider: { [weak authService] in
            try await authService?.getAccessToken() ?? ""
        })
        self.pageMetadata = PageMetadataService()
        self.browserPrice = BrowserPriceService()
        self.attachments = AttachmentsViewModel(sheets: self.sheets, drive: self.drive, appState: self.appState)
        self.inventory = InventoryViewModel(sheets: self.sheets, drive: self.drive, appState: self.appState, attachments: self.attachments)
        self.categories = CategoriesViewModel(sheets: self.sheets, appState: self.appState)
        self.locations = LocationsViewModel(sheets: self.sheets, appState: self.appState)
        self.stores = StoresViewModel(sheets: self.sheets, appState: self.appState)
        self.sources = SourcesViewModel(sheets: self.sheets, appState: self.appState)
        self.lists = ListsViewModel(sheets: self.sheets, appState: self.appState)
        self.combos = CombosViewModel(sheets: self.sheets, appState: self.appState)
        self.trips = TripsViewModel(sheets: self.sheets, appState: self.appState)

        // Forward child view model updates so views observing Session re-render when items/categories load
        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        inventory.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        categories.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        locations.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        stores.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        sources.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        attachments.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] (_: Any) in self?.objectWillChange.send() }
            .store(in: &cancellables)
        lists.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        combos.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        trips.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func bootstrap() async {
        appState.bootstrapStep = "Getting token…"
        // Fail fast if getting the token hangs (common on Mac)
        let gotToken = await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                _ = try? await self.authService.getAccessToken()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        guard gotToken else {
            appState.bootstrapStep = ""
            appState.bootstrapError = "Getting access token timed out. Sign out and try again."
            return
        }

        let email = authService.currentUser?.profile?.email ?? "user"
        let timeout: UInt64 = 60_000_000_000 // 60 seconds
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                await self.appState.bootstrapIfNeeded(sheets: self.sheets, drive: self.drive, userEmail: email)
                if self.appState.bootstrapError == nil, let sid = self.appState.spreadsheetId {
                    await self.inventory.refresh()
                    await self.categories.load()
                    await self.locations.load()
                    await self.stores.load()
                    await self.sources.load()
                    await self.attachments.load()
                    await self.lists.load()
                    await self.combos.load()
                    await self.trips.load()
                }
                return true
            }
            group.addTask { @MainActor in
                try? await Task.sleep(nanoseconds: timeout)
                if self.appState.spreadsheetId == nil, self.appState.bootstrapError == nil {
                    self.appState.bootstrapError = "Setup timed out. Check your internet connection and try again."
                }
                return false
            }
            _ = await group.next()
            group.cancelAll()
        }
        if appState.bootstrapError == nil {
            Task { await prefetchWishlistPricesIfNeeded() }
        }
    }

    /// Runs prefetch if last run was more than 24h ago (or never). Call on app launch and when app becomes active.
    func prefetchWishlistPricesIfNeeded() async {
        let now = Date()
        if let last = UserDefaults.standard.object(forKey: Self.lastPrefetchDateKey) as? Date {
            guard now.timeIntervalSince(last) >= 24 * 3600 else { return }
        }
        await prefetchWishlistPrices()
    }

    /// Returns a stable cache key for a product URL, or nil if the link is empty or invalid.
    func storePriceCacheKey(webLink: String) -> String? {
        let s = webLink.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty,
              let u = URL(string: s),
              u.scheme == "https" || u.scheme == "http" else { return nil }
        return u.absoluteString
    }

    /// Stores a price in the cache for the given URL (e.g. after fetching in item detail). Use this to avoid refetching when opening detail.
    func setCachedStorePrice(url: URL, price: String) {
        var next = storePriceCache
        next[url.absoluteString] = price
        storePriceCache = next
    }

    /// Fetches the product page and caches the parsed price. Returns the price string if found.
    /// For Amazon (and similar) URLs, uses a headless WKWebView so JS-rendered price is captured.
    /// Updates storePriceFetching and storePriceFailed so UI can show loading vs failed.
    func fetchAndCacheStorePrice(for url: URL) async -> String? {
        let key = url.absoluteString
        storePriceFetching = storePriceFetching.union([key])
        defer {
            storePriceFetching = storePriceFetching.subtracting([key])
        }

        let host = url.host?.lowercased() ?? ""
        let useBrowser = host.contains("amazon")

        if useBrowser {
            if let p = await browserPrice.extractPrice(from: url), !p.isEmpty {
                var next = storePriceCache
                next[key] = p
                storePriceCache = next
                storePriceFailed = storePriceFailed.subtracting([key])
                return p
            }
            storePriceFailed = storePriceFailed.union([key])
            return nil
        }

        do {
            let metadata = try await pageMetadata.fetchMetadata(from: url)
            let price = metadata.price?.trimmingCharacters(in: .whitespaces)
            if let p = price, !p.isEmpty {
                var next = storePriceCache
                next[key] = p
                storePriceCache = next
                storePriceFailed = storePriceFailed.subtracting([key])
                return p
            }
        } catch {
            // Don't cache failures; leave cache unchanged for this URL.
        }
        storePriceFailed = storePriceFailed.union([key])
        return nil
    }

    /// Fetches current prices for all wishlist items that have a web link. Runs in background; updates storePriceCache.
    func prefetchWishlistPrices() async {
        guard !isPrefetchingWishlistPrices else { return }
        isPrefetchingWishlistPrices = true
        defer { isPrefetchingWishlistPrices = false }
        // Brief delay so inventory/categories are fully settled
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s
        let items = inventory.items
        let categories = self.categories.categories
        let wishlistIds = Set(categories.filter { Category.isWishlist($0.name) }.map(\.id))
        let wishlistItems = items.filter { wishlistIds.contains($0.categoryId) }
        var urlsToFetch: [URL] = []
        var seen = Set<String>()
        for item in wishlistItems {
            guard let key = storePriceCacheKey(webLink: item.webLink),
                  !seen.contains(key) else { continue }
            seen.insert(key)
            if let url = URL(string: key) {
                urlsToFetch.append(url)
            }
        }
        let keysToFetch = Set(urlsToFetch.map(\.absoluteString))
        storePriceFailed = storePriceFailed.subtracting(keysToFetch)
        for (index, url) in urlsToFetch.enumerated() {
            if index > 0 {
                try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2 s between requests to reduce rate limiting
            }
            _ = await fetchAndCacheStorePrice(for: url)
        }
        UserDefaults.standard.set(Date(), forKey: Self.lastPrefetchDateKey)
    }
}
