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
        }
        #else
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: 0) { Label("Items", systemImage: "square.grid.2x2") }
                NavigationLink(value: 1) { Label("Categories", systemImage: "folder") }
                NavigationLink(value: 2) { Label("Locations", systemImage: "location") }
            }
            .listStyle(.sidebar)
        } detail: {
            if selectedTab == 0 {
                ItemsTabView(viewMode: $itemViewMode)
            } else if selectedTab == 1 {
                CategoriesView()
            } else {
                LocationsView()
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
