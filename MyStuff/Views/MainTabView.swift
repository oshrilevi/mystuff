import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: GoogleAuthService
    @State private var selectedTab = 0

    var body: some View {
        #if os(iOS)
        TabView(selection: $selectedTab) {
            GalleryView()
                .tabItem { Label("Items", systemImage: "square.grid.2x2") }
                .tag(0)
            CategoriesView()
                .tabItem { Label("Categories", systemImage: "folder") }
                .tag(1)
        }
        #else
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: 0) { Label("Items", systemImage: "square.grid.2x2") }
                NavigationLink(value: 1) { Label("Categories", systemImage: "folder") }
            }
            .listStyle(.sidebar)
        } detail: {
            if selectedTab == 0 {
                GalleryView()
            } else {
                CategoriesView()
            }
        }
        #endif
    }
}
