import SwiftUI

/// Three-pane shell: sessions sidebar · chat · context panel.
/// Mirrors the openchamber layout that this app is modelled on.
struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore

    var body: some View {
        GeometryReader { geo in
            let mode = app.layoutMode
            ZStack {
                baseLayout(mode)
                drawerOverlays(mode, width: geo.size.width)
                if app.showCommandPalette {
                    CommandPalette()
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .background(Theme.bg)
            .foregroundStyle(Theme.textPrimary)
            .animation(.easeInOut(duration: 0.2), value: app.showRightSidebar)
            .animation(.easeInOut(duration: 0.2), value: app.sessionsDrawerOpen)
            .animation(.easeOut(duration: 0.15), value: app.showCommandPalette)
            .background(GlobalShortcuts())
            .onAppear { app.updateLayout(forWidth: geo.size.width) }
            .onChange(of: geo.size.width) { width in app.updateLayout(forWidth: width) }
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

    /// Inline panes for the current width. Side panes that don't fit are promoted
    /// to overlay drawers in `drawerOverlays`.
    @ViewBuilder
    private func baseLayout(_ mode: AppModel.LayoutMode) -> some View {
        HStack(spacing: 0) {
            if !mode.isCompact {
                SessionsSidebar()
                    .frame(width: mode.isWide ? 300 : 280)
                Divider().overlay(Theme.border)
            }

            ChatPane()
                .frame(maxWidth: .infinity)

            if mode.isWide && app.showRightSidebar {
                Divider().overlay(Theme.border)
                ContextPane()
                    .frame(width: 360)
                    .transition(.move(edge: .trailing))
            }
        }
    }

    /// Sessions (left) and context (right) drawers shown over the chat when the
    /// window is too narrow to host them inline — the Split View / Stage Manager
    /// path.
    @ViewBuilder
    private func drawerOverlays(_ mode: AppModel.LayoutMode, width: CGFloat) -> some View {
        if mode.isCompact && app.sessionsDrawerOpen {
            scrim { app.sessionsDrawerOpen = false }
            HStack(spacing: 0) {
                SessionsSidebar()
                    .frame(width: min(320, width * 0.86))
                    .background(Theme.panel)
                Divider().overlay(Theme.border)
                Spacer(minLength: 0)
            }
            .transition(.move(edge: .leading))
            .zIndex(6)
        }

        if !mode.isWide && app.showRightSidebar {
            scrim { app.showRightSidebar = false }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Divider().overlay(Theme.border)
                ContextPane()
                    .frame(width: min(380, width * 0.86))
                    .background(Theme.panel)
            }
            .transition(.move(edge: .trailing))
            .zIndex(6)
        }
    }

    private func scrim(_ dismiss: @escaping () -> Void) -> some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .onTapGesture(perform: dismiss)
            .transition(.opacity)
            .zIndex(5)
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
