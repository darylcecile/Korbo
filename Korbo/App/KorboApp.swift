import SwiftUI

@main
struct KorboApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var store = KorboStore()
    @StateObject private var github = GitHubStore()
    @StateObject private var cloud = CloudStore()
    @ObservedObject private var intents = IntentRouter.shared
    @ObservedObject private var appearance = AppearanceStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .modifier(RootEnvironment(appModel: appModel, store: store, github: github, cloud: cloud, appearance: appearance))
                .task {
                    // Attempt to connect to the selected server on launch. If no
                    // credentials are stored yet this surfaces a failed state and
                    // the user can open the connection sheet. Both the connect and
                    // the notification prompt are skipped while first-run onboarding
                    // is up, so the welcome flow isn't interrupted by a system
                    // permission dialog or a spurious failed-connection banner.
                    if !appModel.showOnboarding {
                        NotificationManager.shared.requestAuthorizationIfNeeded()
                    }
                    LiveActivityController.shared.endStaleOnLaunch()
                    cloud.attach(korbo: store)
                    await cloud.bootstrap()
                    if !appModel.showOnboarding, store.servers.selectedServer != nil {
                        await store.connect()
                    }
                }
                .onChange(of: intents.pending) { _, pending in
                    guard let pending else { return }
                    Task { await handleIntent(pending) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.reconcileLiveActivitiesOnForeground()
                        // A self-hosted session started via `korbo up` while the app
                        // was backgrounded won't surface until we re-list, so refresh
                        // on foreground to keep the cloud switcher current.
                        if cloud.isSignedIn {
                            Task { await cloud.refreshSessions() }
                        }
                    }
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
                .modifier(RootEnvironment(appModel: appModel, store: store, github: github, cloud: cloud, appearance: appearance))
                .task(id: sessionID) {
                    cloud.attach(korbo: store)
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
    let cloud: CloudStore
    let appearance: AppearanceStore

    func body(content: Content) -> some View {
        content
            .environmentObject(appModel)
            .environmentObject(store)
            .environmentObject(github)
            .environmentObject(cloud)
            .environmentObject(appearance)
            .preferredColorScheme(.dark)
            .tint(appearance.accentColor)
            .environment(\.dynamicTypeSize, appearance.effectiveDynamicTypeSize)
    }
}
