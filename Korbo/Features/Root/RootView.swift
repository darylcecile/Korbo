import SwiftUI

/// Three-pane shell: sessions sidebar · chat · context panel.
/// Mirrors the openchamber layout that this app is modelled on.
struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore
    @EnvironmentObject private var cloud: CloudStore
    /// Observed so an accent/theme change re-resolves every static `Theme.*`
    /// color across the whole tree (see `.id` below), not just views that
    /// happen to observe the store.
    @ObservedObject private var appearance = AppearanceStore.shared

    var body: some View {
        GeometryReader { geo in
            let mode = app.layoutMode
            ZStack {
                baseLayout(mode, width: geo.size.width)
                drawerOverlays(mode, width: geo.size.width)
                leftEdgeRevealGesture(mode)
                ConnectionBanner()
                    .zIndex(8)
                WorkspaceNoticeBanner()
                    .zIndex(8)
                if case .failed = store.status {
                    ConnectionFailureView()
                        .environmentObject(app)
                        .environmentObject(store)
                        .transition(.opacity)
                        .zIndex(9)
                }
                if app.showCommandPalette {
                    CommandPalette()
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .background(Theme.bg)
            .ignoresSafeArea(.container, edges: .bottom)
            .foregroundStyle(Theme.textPrimary)
            .animation(.easeInOut(duration: 0.2), value: app.showLeftSidebar)
            .animation(.easeInOut(duration: 0.2), value: app.showRightSidebar)
            .animation(.easeInOut(duration: 0.2), value: app.sessionsDrawerOpen)
            .animation(.easeInOut(duration: 0.2), value: store.status)
            .animation(.easeOut(duration: 0.15), value: app.showCommandPalette)
            .background(GlobalShortcuts())
            .onAppear { app.updateLayout(forWidth: geo.size.width) }
            .onChange(of: geo.size.width) { width in app.updateLayout(forWidth: width) }
            .sheet(isPresented: $app.showConnectionSheet) {
                ConnectionSheet()
                    .environmentObject(store)
                    .environmentObject(app)
            }
            .sheet(isPresented: $app.showCloudSheet) {
                CloudDashboardView()
                    .environmentObject(app)
                    .environmentObject(store)
                    .environmentObject(cloud)
            }
            .sheet(isPresented: $app.showInstancePicker) {
                InstancePickerView()
                    .environmentObject(cloud)
                    .environmentObject(app)
            }
            .sheet(isPresented: $app.showSettingsSheet) {
                SettingsView()
                    .environmentObject(app)
                    .environmentObject(store)
            }
            .sheet(isPresented: $app.showShortcutsCheatSheet) {
                ShortcutsCheatSheet()
                    .environmentObject(app)
            }
            .fullScreenCover(isPresented: $app.showOnboarding) {
                OnboardingView()
                    .environmentObject(app)
                    .environmentObject(cloud)
            }
            .userActivity(Handoff.sessionActivityType, isActive: store.selectedSessionID != nil) { activity in
                store.decorateHandoff(activity)
            }
            .onContinueUserActivity(Handoff.sessionActivityType) { activity in
                Task { await store.continueHandoff(activity) }
            }
        }
        .id("\(appearance.accent.rawValue)-\(appearance.theme.rawValue)")
    }

    /// Inline panes for the current width. Side panes that don't fit are promoted
    /// to overlay drawers in `drawerOverlays`.
    @ViewBuilder
    private func baseLayout(_ mode: AppModel.LayoutMode, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if !mode.isCompact && app.showLeftSidebar {
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
                    .frame(width: app.contextPaneInlineWidth(available: width))
                    .transition(.move(edge: .trailing))
            }
        }
    }

    @ViewBuilder
    private func leftEdgeRevealGesture(_ mode: AppModel.LayoutMode) -> some View {
        if !mode.isCompact && !app.showLeftSidebar {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: 16)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onEnded { value in
                                if value.translation.width > 40 {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        app.showLeftSidebar = true
                                    }
                                }
                            }
                    )
                Spacer(minLength: 0)
            }
            .zIndex(7)
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

/// A thin top banner that surfaces transient non-connected states. Hidden while
/// connected or failed so it never competes with the connection failure screen.
private struct ConnectionBanner: View {
    @EnvironmentObject private var store: KorboStore

    var body: some View {
        VStack(spacing: 0) {
            if showsBanner {
                banner
                    .transition(.move(edge: .top).combined(with: .opacity))
                Spacer(minLength: 0)
            }
        }
        .allowsHitTesting(false)
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
        default:
            Image(systemName: "wifi.slash")
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var title: String {
        switch store.status {
        case .connecting: return "Connecting…"
        case .disconnected: return "Disconnected"
        case .connected, .failed: return ""
        }
    }

    private var detail: String? {
        if case .connecting = store.status { return nil }
        return store.lastError
    }

    private var showsBanner: Bool {
        switch store.status {
        case .connecting, .disconnected: return true
        case .connected, .failed: return false
        }
    }
}

struct ConnectionFailureView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: KorboStore
    @State private var retrying = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 14) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(Theme.removed)
                            Text(title)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(reason)
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 12) {
                            accentCapsuleButton("Try again", busy: retrying) {
                                guard !retrying else { return }
                                retrying = true
                                Task {
                                    await store.connect()
                                    retrying = false
                                }
                            }
                            connectCard(icon: "rectangle.2.swap",
                                        title: "Choose a different instance",
                                        subtitle: "Switch to another cloud instance or one of your machines",
                                        prominent: false) {
                                app.showInstancePicker = true
                            }
                            connectCard(icon: "slider.horizontal.3",
                                        title: "Configure connection",
                                        subtitle: "Edit the server URL, authentication, or saved servers",
                                        prominent: false) {
                                app.showConnectionSheet = true
                            }
                        }
                    }
                    .padding(.vertical, 40)
                    .frame(minHeight: geo.size.height)
                    .readableColumn()
                }
            }
        }
    }

    private var background: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.18), .clear],
                           center: .top, startRadius: 0, endRadius: 540)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var title: String {
        if let name = store.servers.selectedServer?.name, !name.isEmpty {
            return "Can’t reach \(name)"
        }
        return "Connection failed"
    }

    private var reason: String {
        if case .failed(let message) = store.status, !message.isEmpty {
            return message
        }
        if let error = store.lastError, !error.isEmpty {
            return error
        }
        return "Korbo couldn’t connect to the selected opencode server."
    }

    private func accentCapsuleButton(_ title: String,
                                     busy: Bool = false,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Self.onAccent)
                    .opacity(busy ? 0 : 1)
                if busy {
                    ProgressView().tint(Self.onAccent)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Theme.accent))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func connectCard(icon: String,
                             title: String,
                             subtitle: String,
                             prominent: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(prominent ? Self.onAccent : Theme.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(prominent ? Self.onAccent : Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(prominent ? Self.onAccent.opacity(0.75) : Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(prominent ? Self.onAccent.opacity(0.5) : Theme.textTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prominent ? Theme.accent : Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private static let onAccent = Color(hex: 0x111114)
}

private extension View {
    func readableColumn() -> some View {
        self
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
    }
}

/// A thin, dismissable top banner that explains how the connected cloud
/// instance's workspace was restored on resume — e.g. it was re-cloned from
/// origin (so local-only edits weren't carried over), or restored from a
/// possibly-stale snapshot. Only shown while connected and when the cloud store
/// has flagged something worth surfacing.
private struct WorkspaceNoticeBanner: View {
    @EnvironmentObject private var store: KorboStore
    @EnvironmentObject private var cloud: CloudStore

    var body: some View {
        VStack(spacing: 0) {
            if store.status.isConnected, let notice = cloud.workspaceNotice {
                banner(notice)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Spacer(minLength: 0)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cloud.workspaceNotice)
        .animation(.easeInOut(duration: 0.2), value: store.status)
    }

    private func banner(_ notice: CloudStore.WorkspaceNotice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(notice))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(notice))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail(notice))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                cloud.dismissWorkspaceNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
    }

    private func icon(_ notice: CloudStore.WorkspaceNotice) -> String {
        switch notice {
        case .reclonedFromOrigin: return "arrow.triangle.2.circlepath"
        case .restoredStale:      return "clock.arrow.circlepath"
        }
    }

    private func title(_ notice: CloudStore.WorkspaceNotice) -> String {
        switch notice {
        case .reclonedFromOrigin: return "Workspace re-cloned from origin"
        case .restoredStale:      return "Workspace may be slightly out of date"
        }
    }

    private func detail(_ notice: CloudStore.WorkspaceNotice) -> String {
        switch notice {
        case .reclonedFromOrigin:
            return "No snapshot was available, so files were pulled fresh from GitHub. Uncommitted local-only changes from before the last sleep weren't restored."
        case .restoredStale:
            return "Restored from a snapshot that may predate your most recent edits."
        }
    }
}

/// A single hardware-keyboard shortcut, used purely for *display* in
/// `ShortcutsCheatSheet`. The live bindings are registered explicitly in
/// `GlobalShortcuts` (see the note there for why this isn't a `ForEach`);
/// keep this catalogue in sync with those buttons.
struct KorboShortcut: Identifiable {
    let id = UUID()
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let title: String
    let group: String

    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += keyLabel
        return s
    }

    private var keyLabel: String {
        switch key.character {
        case "\r": return "↵"
        case " ":  return "Space"
        case "\\": return "\\"
        default:   return String(key.character).uppercased()
        }
    }

    /// The complete, ordered catalogue shown in the cheat sheet.
    static let all: [KorboShortcut] = [
        // Navigation
        .init(key: "p", modifiers: .command, title: "Command palette", group: "Navigation"),
        .init(key: "k", modifiers: .command, title: "Search everything", group: "Navigation"),
        .init(key: "l", modifiers: [.command, .shift], title: "Focus composer", group: "Navigation"),
        // Panels
        .init(key: "\\", modifiers: .command, title: "Toggle right panel", group: "Panels"),
        .init(key: "1", modifiers: .command, title: "Show Git", group: "Panels"),
        .init(key: "2", modifiers: .command, title: "Show Files", group: "Panels"),
        .init(key: "3", modifiers: .command, title: "Show Context", group: "Panels"),
        .init(key: "t", modifiers: .command, title: "Toggle terminal", group: "Panels"),
        // Session
        .init(key: "n", modifiers: .command, title: "New session", group: "Session"),
        .init(key: ".", modifiers: .command, title: "Stop generation", group: "Session"),
        .init(key: .return, modifiers: .command, title: "Send message", group: "Session"),
        // App
        .init(key: ",", modifiers: .command, title: "Settings", group: "App"),
        .init(key: "/", modifiers: .command, title: "Keyboard shortcuts", group: "App"),
    ]
}

/// Invisible buttons whose only job is to register window-wide hardware-keyboard
/// shortcuts (and populate the ⌘-hold discoverability HUD). Kept off-screen so
/// they never affect layout.
///
/// Registration is intentionally written as explicit `Button`s grouped in
/// `Group`s (not a `ForEach`): SwiftUI only reliably installs the keyboard
/// shortcut of the *first* dynamically-generated button when they share a
/// zero-size overlapping container, so a `ForEach` silently drops every
/// shortcut after the first. The grouped explicit form is the proven layout.
/// The cheat sheet (`ShortcutsCheatSheet`) reads `KorboShortcut.all` for its
/// display, so the two stay in lockstep — keep both in sync when editing.
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
                Button("Focus Composer") { app.focusComposer() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Toggle Right Panel") { app.showRightSidebar.toggle() }
                    .keyboardShortcut("\\", modifiers: .command)
                Button("Show Git") { app.showRightTab(.git) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Show Files") { app.showRightTab(.files) }
                    .keyboardShortcut("2", modifiers: .command)
            }
            Group {
                Button("Show Context") { app.showRightTab(.context) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Toggle Terminal") { app.toggleTerminal() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("New Session") { Task { await store.createSession() } }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Stop Generation") { Task { await store.abort() } }
                    .keyboardShortcut(".", modifiers: .command)
                Button("Settings") { app.showSettingsSheet = true }
                    .keyboardShortcut(",", modifiers: .command)
                Button("Keyboard Shortcuts") { app.toggleShortcutsCheatSheet() }
                    .keyboardShortcut("/", modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// Grouped, read-only reference of every hardware-keyboard shortcut, shown as a
/// sheet via ⌘/. Sourced entirely from `KorboShortcut.all`.
struct ShortcutsCheatSheet: View {
    @EnvironmentObject private var app: AppModel

    private var groups: [(name: String, items: [KorboShortcut])] {
        var order: [String] = []
        var bucket: [String: [KorboShortcut]] = [:]
        for s in KorboShortcut.all {
            if bucket[s.group] == nil { order.append(s.group) }
            bucket[s.group, default: []].append(s)
        }
        return order.map { ($0, bucket[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.items) { shortcut in
                            HStack {
                                Text(shortcut.title)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(shortcut.display)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Theme.panelRaised)
                                    )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Keyboard Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { app.showShortcutsCheatSheet = false }
                }
            }
        }
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
