import SwiftUI

@main
struct KorboApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var store = KorboStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task {
                    // Attempt to connect to the selected server on launch. If no
                    // credentials are stored yet this surfaces a failed state and
                    // the user can open the connection sheet.
                    if store.servers.selectedServer != nil {
                        await store.connect()
                    }
                }
        }
    }
}
