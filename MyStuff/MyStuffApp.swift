import SwiftUI

@main
struct MyStuffApp: App {
    @StateObject private var authService = GoogleAuthService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
        }
    }
}
