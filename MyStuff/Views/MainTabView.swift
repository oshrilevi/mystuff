import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum MainSidebarSelection: Hashable {
    case items
    case lists
    case combos
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
                NavigationLink(value: MainSidebarSelection.combos) { Label("Combos", systemImage: "square.stack.3d.up") }
                NavigationLink(value: MainSidebarSelection.lists) { Label("My Lists", systemImage: "checklist") }
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
                .padding(.bottom, 10)
            }
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selection {
                case .items:
                    ItemsTabView(viewMode: $itemViewMode)
                case .lists:
                    ListsView()
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
        #endif
    }
}

#if os(macOS)
private struct SettingsMenuButton: View {
    @Binding var selection: MainSidebarSelection
    @EnvironmentObject var session: Session
    @State private var isExportingPDF = false
    @State private var isExportingZIP = false
    @State private var isExpanded = false
    @State private var hoveredRow: SettingsRow?

    private enum SettingsRow: Hashable {
        case categories
        case locations
        case stores
        case sources
        case exportCSV
        case exportPDF
        case exportZIP
    }

    var body: some View {
        VStack(spacing: 6) {
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
                    .frame(maxWidth: .infinity, minHeight: 32)
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
            Label(title, systemImage: systemImage)
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
        case .stores:
            return selection == .storesList
        case .sources:
            return selection == .sourcesList
        case .exportCSV, .exportPDF, .exportZIP:
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
            // Ensure combos are available from app launch so item context menus
            // can show which combos an item belongs to without first visiting Combos.
            await session.combos.ensureLoaded()
            await session.prefetchWishlistPricesIfNeeded()
        }
    }
}
