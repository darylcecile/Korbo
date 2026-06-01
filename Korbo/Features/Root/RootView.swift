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
                baseLayout(mode, width: geo.size.width)
                drawerOverlays(mode, width: geo.size.width)
                ConnectionBanner()
                    .zIndex(8)
                if app.showCommandPalette {
                    CommandPalette()
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .background(Theme.bg)
            .ignoresSafeArea(.container, edges: .bottom)
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
    private func baseLayout(_ mode: AppModel.LayoutMode, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if !mode.isCompact {
                SessionsSidebar()
                    .frame(width: mode.isWide ? app.sessionsPaneWidth : 280)
                if mode.isWide {
                    PaneResizeHandle { dx in app.resizeSessionsPane(by: dx) }
                } else {
                    Divider().overlay(Theme.border)
                }
            }

            Group {
                switch app.centerPane {
                case .terminal:
                    TerminalPane()
                case .files:
                    FileViewerPane()
                case .chat:
                    ChatPane()
                }
            }
            .frame(maxWidth: .infinity)

            if mode.isWide && app.showRightSidebar {
                PaneResizeHandle { dx in app.resizeContextPane(by: -dx, available: width) }
                ContextPane()
                    .frame(width: app.contextPaneWidth.clamped(to: AppModel.contextWidthRange.lowerBound...min(AppModel.contextWidthRange.upperBound, width * 0.6)))
                    .transition(.move(edge: .trailing))
            }
        }
    }

    /// Width used for the context pane when shown as an overlay drawer (narrow
    /// windows): honour the user's chosen width but never exceed the window.
    private func drawerContextWidth(_ width: CGFloat) -> CGFloat {
        min(app.contextPaneWidth, width * 0.92)
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
                    .frame(width: drawerContextWidth(width))
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

/// A thin top banner that surfaces non-connected states (connecting / failed /
/// disconnected) with a one-tap retry. Hidden entirely while connected so it
/// never steals space from the panes.
private struct ConnectionBanner: View {
    @EnvironmentObject private var store: KorboStore
    @State private var retrying = false

    var body: some View {
        VStack(spacing: 0) {
            if !store.status.isConnected {
                banner
                    .transition(.move(edge: .top).combined(with: .opacity))
                Spacer(minLength: 0)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.status)
    }

    private var banner: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let detail = detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if showsRetry {
                Button {
                    guard !retrying else { return }
                    retrying = true
                    Task {
                        await store.connect()
                        retrying = false
                    }
                } label: {
                    Text(retrying ? "Retrying…" : "Retry")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(retrying)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
    }

    @ViewBuilder
    private var icon: some View {
        switch store.status {
        case .connecting:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.removed)
        default:
            Image(systemName: "wifi.slash")
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var title: String {
        switch store.status {
        case .connecting: return "Connecting…"
        case .failed: return "Connection failed"
        case .disconnected: return "Disconnected"
        case .connected: return ""
        }
    }

    private var detail: String? {
        if case .connecting = store.status { return nil }
        return store.lastError
    }

    private var showsRetry: Bool {
        switch store.status {
        case .failed, .disconnected: return true
        case .connecting, .connected: return false
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
                Button("Show Context") { app.showRightTab(.context) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Toggle Terminal") { app.toggleTerminal() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Settings") { app.showSettingsSheet = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// A 1-pt divider with a wider invisible hit target that lets the user drag to
/// resize the adjacent pane. Reports the incremental horizontal delta so callers
/// can apply (and clamp/persist) it however they like.
private struct PaneResizeHandle: View {
    let onChange: (CGFloat) -> Void
    @State private var lastTranslation: CGFloat = 0
    @State private var active = false

    var body: some View {
        Rectangle()
            .fill(active ? Theme.accent : Theme.border)
            .frame(width: active ? 2 : 1)
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if !active { active = true }
                                let dx = value.translation.width - lastTranslation
                                lastTranslation = value.translation.width
                                onChange(dx)
                            }
                            .onEnded { _ in
                                lastTranslation = 0
                                active = false
                            }
                    )
            }
            .hoverEffect(.highlight)
    }
}

#Preview {
    RootView()
        .environmentObject(AppModel())
        .environmentObject(KorboStore())
}
