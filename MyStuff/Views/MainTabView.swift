import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: GoogleAuthService
    @State private var selectedTab = 0
    @State private var itemViewMode: ItemViewMode = .grid

    var body: some View {
        #if os(iOS)
        TabView(selection: $selectedTab) {
            ItemsTabView(viewMode: $itemViewMode)
                .tabItem { Label("Items", systemImage: "square.grid.2x2") }
                .tag(0)
            CategoriesView()
                .tabItem { Label("Categories", systemImage: "folder") }
                .tag(1)
            LocationsView()
                .tabItem { Label("Locations", systemImage: "location") }
                .tag(2)
            StoreBrowserView(store: .amazon)
                .tabItem { Label("Amazon", systemImage: "cart") }
                .tag(3)
            StoreBrowserView(store: .bhPhoto)
                .tabItem { Label("B&H", systemImage: "camera") }
                .tag(4)
        }
        #else
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("Items") {
                    NavigationLink(value: 0) { Label("Items", systemImage: "square.grid.2x2") }
                }
                Section("Settings") {
                    NavigationLink(value: 1) { Label("Categories", systemImage: "folder") }
                    NavigationLink(value: 2) { Label("Locations", systemImage: "location") }
                }
                Section("Stores") {
                    NavigationLink(value: 3) { Label("Amazon", systemImage: "cart") }
                    NavigationLink(value: 4) { Label("B&H Photo", systemImage: "camera") }
                }
            }
            .listStyle(.sidebar)
        } detail: {
            if selectedTab == 0 {
                ItemsTabView(viewMode: $itemViewMode)
            } else if selectedTab == 1 {
                CategoriesView()
            } else if selectedTab == 2 {
                LocationsView()
            } else if selectedTab == 3 {
                StoreBrowserView(store: .amazon)
            } else if selectedTab == 4 {
                StoreBrowserView(store: .bhPhoto)
            } else {
                EmptyView()
            }
        }
        #endif
    }
}

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
