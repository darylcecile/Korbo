import SwiftUI

@main
struct KorboApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
