import SwiftUI

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
    @State private var selection: MainSidebarSelection = .items
    @State private var itemViewMode: ItemViewMode = .grid

    var body: some View {
        #if os(iOS)
        TabView(selection: $selection) {
            ItemsTabView(viewMode: $itemViewMode)
                .tabItem { Label("Items", systemImage: "square.grid.2x2") }
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
                .tabItem { Label("YouTube", systemImage: "play.rectangle") }
                .tag(MainSidebarSelection.youtube)
        }
        .onChange(of: session.requestedSidebarSelection) { _, newValue in
            if let sel = newValue {
                selection = sel
                session.requestedSidebarSelection = nil
            }
        }
        #else
        NavigationSplitView {
            List(selection: $selection) {
                Section("Items") {
                    NavigationLink(value: MainSidebarSelection.items) { Label("Items", systemImage: "square.grid.2x2") }
                }
                Section("Settings") {
                    NavigationLink(value: MainSidebarSelection.categories) { Label("Categories", systemImage: "folder") }
                    NavigationLink(value: MainSidebarSelection.locations) { Label("Locations", systemImage: "location") }
                    NavigationLink(value: MainSidebarSelection.storesList) { Label("Stores", systemImage: "cart") }
                    NavigationLink(value: MainSidebarSelection.sourcesList) { Label("Sources", systemImage: "link") }
                }
                Section("Media") {
                    NavigationLink(value: MainSidebarSelection.youtube) { Label("YouTube", systemImage: "play.rectangle") }
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
        #endif
    }
}

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
    @Binding var viewMode: ItemViewMode

    var body: some View {
        Group {
            if viewMode == .grid {
                GalleryView(viewMode: $viewMode)
            } else {
                ItemsListView(viewMode: $viewMode)
            }
        }
    }
}
