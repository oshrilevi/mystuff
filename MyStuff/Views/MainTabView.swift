import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum MainSidebarSelection: Hashable {
    case items
    case categories
    case locations
    case storesList
    case store(UserStore)
    case sourcesList
    case source(UserSource)
    case youtube
}

struct MainTabView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var authService: GoogleAuthService
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: MainSidebarSelection = .items
    @State private var itemViewMode: ItemViewMode = .grid
    var body: some View {
        #if os(iOS)
        TabView(selection: $selection) {
            ItemsTabView(viewMode: $itemViewMode)
                .tabItem { Label("My Stuff", systemImage: "square.grid.2x2") }
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
        #else
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: MainSidebarSelection.items) { Label("My Stuff", systemImage: "square.grid.2x2") }
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
                HStack {
                    SettingsMenuButton(selection: $selection)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selection {
                case .items:
                    ItemsTabView(viewMode: $itemViewMode)
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
        #endif
    }
}

#if os(macOS)
private struct SettingsMenuButton: View {
    @Binding var selection: MainSidebarSelection
    @EnvironmentObject var session: Session
    @State private var isExportingPDF = false
    @State private var isExportingZIP = false

    var body: some View {
        Menu {
            Section("Settings") {
                Button {
                    selection = .categories
                } label: { Label("Categories", systemImage: "folder") }

                Button {
                    selection = .locations
                } label: { Label("Locations", systemImage: "location") }

                Button {
                    selection = .storesList
                } label: { Label("Stores", systemImage: "cart") }

                Button {
                    selection = .sourcesList
                } label: { Label("Sources", systemImage: "link") }
            }
            Section("Exports") {
                Button {
                    exportCSV()
                } label: { Label("Export as CSV", systemImage: "table") }

                Button {
                    isExportingPDF = true
                    Task {
                        await exportPDF()
                        await MainActor.run { isExportingPDF = false }
                    }
                } label: { Label("Export as PDF", systemImage: "doc.richtext") }

                Button {
                    isExportingZIP = true
                    Task {
                        await exportZIP()
                        await MainActor.run { isExportingZIP = false }
                    }
                } label: { Label("Export as ZIP", systemImage: "archivebox") }
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.title2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
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
        notification.title = "MyStuff Backup Complete"
        notification.informativeText = "Saved to Downloads/\(destination.lastPathComponent)"
        NSUserNotificationCenter.default.deliver(notification)
        #endif
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
            if viewMode == .grid {
                GalleryView(viewMode: $viewMode)
            } else {
                ItemsListView(viewMode: $viewMode)
            }
        }
        .task {
            await session.prefetchWishlistPricesIfNeeded()
        }
    }
}
