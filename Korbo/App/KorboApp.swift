import SwiftUI

@main
struct KorboApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var store = KorboStore()
    @ObservedObject private var intents = IntentRouter.shared
    @ObservedObject private var appearance = AppearanceStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .environmentObject(store)
                .environmentObject(appearance)
                .preferredColorScheme(.dark)
                .tint(appearance.accentColor)
                .environment(\.dynamicTypeSize, appearance.effectiveDynamicTypeSize)
                .task {
                    // Attempt to connect to the selected server on launch. If no
                    // credentials are stored yet this surfaces a failed state and
                    // the user can open the connection sheet.
                    if store.servers.selectedServer != nil {
                        await store.connect()
                    }
                }
                .onChange(of: intents.pending) { _, pending in
                    guard let pending else { return }
                    Task { await handleIntent(pending) }
                }
        }
    }

    @MainActor
    private func handleIntent(_ intent: IntentRouter.PendingIntent) async {
        defer { intents.pending = nil }

        // Ensure we're connected before acting
        if !store.status.isConnected {
            await store.connect()
        }

        switch intent {
        case .newSession:
            await store.createSession()
        case .sendPrompt(let text):
            if store.selectedSessionID == nil {
                await store.createSession()
            }
            await store.sendPrompt(text)
        }
    }
}
