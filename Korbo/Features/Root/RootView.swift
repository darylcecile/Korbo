import SwiftUI

/// Three-pane shell: sessions sidebar · chat · context panel.
/// Mirrors the openchamber layout that this app is modelled on.
struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore

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
        .background(GlobalShortcuts())
        .overlay {
            if app.showCommandPalette {
                CommandPalette()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.15), value: app.showCommandPalette)
        .sheet(isPresented: $app.showConnectionSheet) {
            ConnectionSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $app.showSettingsSheet) {
            SettingsView()
                .environmentObject(app)
                .environmentObject(store)
        }
    }
}

/// Invisible buttons whose only job is to register window-wide hardware-keyboard
/// shortcuts (and populate the ⌘-hold discoverability HUD). Kept off-screen so
/// they never affect layout.
private struct GlobalShortcuts: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore

    var body: some View {
        ZStack {
            Group {
                Button("Command Palette") { app.toggleCommandPalette() }
                    .keyboardShortcut("p", modifiers: .command)
                Button("Search Everything") { app.toggleCommandPalette() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("New Session") { Task { await store.createSession() } }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Stop Generation") { Task { await store.abort() } }
                    .keyboardShortcut(".", modifiers: .command)
                Button("Focus Composer") { app.focusComposer() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Toggle Right Panel") { app.showRightSidebar.toggle() }
                    .keyboardShortcut("\\", modifiers: .command)
            }
            Group {
                Button("Show Git") { app.showRightTab(.git) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Show Files") { app.showRightTab(.files) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Show Terminal") { app.showRightTab(.terminal) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Show Context") { app.showRightTab(.context) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Settings") { app.showSettingsSheet = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

#Preview {
    RootView()
        .environmentObject(AppModel())
        .environmentObject(KorboStore())
}
