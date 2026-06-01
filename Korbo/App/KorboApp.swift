import SwiftUI

@main
struct KorboApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var store = KorboStore()
    @StateObject private var github = GitHubStore()
    @ObservedObject private var intents = IntentRouter.shared
    @ObservedObject private var appearance = AppearanceStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .modifier(RootEnvironment(appModel: appModel, store: store, github: github, appearance: appearance))
                .task {
                    // Attempt to connect to the selected server on launch. If no
                    // credentials are stored yet this surfaces a failed state and
                    // the user can open the connection sheet.
                    NotificationManager.shared.requestAuthorizationIfNeeded()
                    LiveActivityController.shared.endStaleOnLaunch()
                    if store.servers.selectedServer != nil {
                        await store.connect()
                    }
                }
                .onChange(of: intents.pending) { _, pending in
                    guard let pending else { return }
                    Task { await handleIntent(pending) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.reconcileLiveActivitiesOnForeground() }
                }
        }

        // Dedicated session window (iPad Stage Manager / multi-window). Opened via
        // the "Open in New Window" session context-menu action, which calls
        // `openWindow(value:)` with a session id. The same shared `appModel` /
        // `store` instances back every scene (a SwiftUI `@StateObject` on the App
        // is created once for the whole app), so the new window reuses the live
        // connection and simply focuses the requested session.
        WindowGroup(for: String.self) { $sessionID in
            SessionWindowView(sessionID: sessionID)
                .modifier(RootEnvironment(appModel: appModel, store: store, github: github, appearance: appearance))
                .task(id: sessionID) {
                    if store.servers.selectedServer != nil, !store.status.isConnected {
                        await store.connect()
                    }
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

/// Shared environment setup applied to the root of every scene so the main
/// window and any session windows look and behave identically.
private struct RootEnvironment: ViewModifier {
    let appModel: AppModel
    let store: KorboStore
    let github: GitHubStore
    let appearance: AppearanceStore

    func body(content: Content) -> some View {
        content
            .environmentObject(appModel)
            .environmentObject(store)
            .environmentObject(github)
            .environmentObject(appearance)
            .preferredColorScheme(.dark)
            .tint(appearance.accentColor)
            .environment(\.dynamicTypeSize, appearance.effectiveDynamicTypeSize)
    }
}
