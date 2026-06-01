import SwiftUI

/// Root of a dedicated session window (iPad Stage Manager / multi-window).
///
/// Opened from the sessions sidebar via `openWindow(value: sessionID)`. It reuses
/// the existing `ChatPane` so the window shows the same chat UI as the main
/// window, scoped to the requested session id.
///
/// NOTE (v1 limitation): the app keeps a single shared `KorboStore` with one
/// `selectedSessionID`. Focusing a session here selects it in that shared store,
/// so the main window's chat follows the same selection. This window therefore
/// mirrors the currently-selected session rather than hosting a fully
/// independent second session. Making windows track sessions independently would
/// require the store/AppModel to support per-scene selection, which is out of
/// scope here.
struct SessionWindowView: View {
    let sessionID: String?

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore
    @ObservedObject private var appearance = AppearanceStore.shared

    var body: some View {
        ChatPane()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .ignoresSafeArea(.container, edges: .bottom)
            .foregroundStyle(Theme.textPrimary)
            .task(id: sessionID) {
                guard let sessionID else { return }
                app.showChat()
                if store.selectedSessionID != sessionID {
                    await store.selectSession(sessionID)
                }
            }
            .id("\(appearance.accent.rawValue)-\(appearance.theme.rawValue)")
    }
}
