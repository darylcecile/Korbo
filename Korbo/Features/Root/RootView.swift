import SwiftUI

/// Three-pane shell: sessions sidebar · chat · context panel.
/// Mirrors the openchamber layout that this app is modelled on.
struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SessionsSidebar()
                .frame(width: 300)

            Divider().overlay(Theme.border)

            ChatPane()
                .frame(maxWidth: .infinity)

            if app.showRightSidebar {
                Divider().overlay(Theme.border)
                ContextPane()
                    .frame(width: 360)
                    .transition(.move(edge: .trailing))
            }
        }
        .background(Theme.bg)
        .foregroundStyle(Theme.textPrimary)
        .animation(.easeInOut(duration: 0.2), value: app.showRightSidebar)
    }
}

#Preview {
    RootView().environmentObject(AppModel())
}
