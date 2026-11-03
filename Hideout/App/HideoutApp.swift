import SwiftUI

@main
struct HideoutApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var vault = VaultStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(vault)
        }
    }
}
