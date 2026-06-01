import SwiftUI

/// Top-level UI state for the shell. Networking/session state will hang off
/// this as the app is built out per the PRD.
@MainActor
final class AppModel: ObservableObject {
    @Published var showRightSidebar = true
    @Published var rightTab: RightTab = .git
    @Published var showConnectionSheet = false
    @Published var showSettingsSheet = false

    /// When true the middle column shows the terminal instead of the chat. The
    /// terminal lives in the wide centre pane (toggled from the sessions toolbar)
    /// so it gets real width — and the right sidebar can still be collapsed to
    /// widen it further.
    @Published var showTerminal = false

    /// Command palette (⌘P / ⌘K) overlay.
    @Published var showCommandPalette = false

    /// The chat composer text, lifted here so the command palette (and future
    /// `@`/`/`/`!` autocomplete) can prefill it. `ChatPane` binds its TextField
    /// to this and clears it on send.
    @Published var composerDraft: String = ""
    /// Bumped to request keyboard focus on the composer; `ChatPane` observes it.
    @Published var focusComposerToken = 0

    /// Width-derived layout mode (drives adaptive 3/2/1-pane shell for Split View
    /// and Stage Manager). Updated by `RootView` from a `GeometryReader`.
    @Published var layoutMode: LayoutMode = .wide
    /// In compact mode the sessions sidebar is presented as an overlay drawer
    /// rather than inline; this controls its visibility.
    @Published var sessionsDrawerOpen = false

    func toggleCommandPalette() { showCommandPalette.toggle() }
    func toggleTerminal() { showTerminal.toggle() }
    func focusComposer() { focusComposerToken &+= 1 }
    func toggleSessionsDrawer() { sessionsDrawerOpen.toggle() }

    /// Apply a new width-derived layout mode, auto-collapsing side panels as the
    /// window narrows and restoring the context panel when it widens back out.
    func updateLayout(forWidth width: CGFloat) {
        let new = LayoutMode(width: width)
        guard new != layoutMode else { return }
        layoutMode = new
        switch new {
        case .wide:
            showRightSidebar = true
        case .medium, .compact:
            showRightSidebar = false
            sessionsDrawerOpen = false
        }
    }

    /// Breakpoints for the adaptive shell. `compact` ≈ Slide Over / narrow Stage
    /// Manager, `medium` ≈ portrait / half-screen, `wide` ≈ full landscape.
    enum LayoutMode {
        case compact, medium, wide

        init(width: CGFloat) {
            if width >= 1080 { self = .wide }
            else if width >= 720 { self = .medium }
            else { self = .compact }
        }

        var isWide: Bool { self == .wide }
        var isCompact: Bool { self == .compact }
    }

    /// Reveal the right sidebar on a specific tab.
    func showRightTab(_ tab: RightTab) {
        rightTab = tab
        showRightSidebar = true
    }

    enum RightTab: String, CaseIterable, Identifiable {
        case git, files, context
        var id: String { rawValue }
        var title: String { rawValue }
        var systemImage: String {
            switch self {
            case .git: return "arrow.triangle.branch"
            case .files: return "folder"
            case .context: return "doc.text.magnifyingglass"
            }
        }
    }
}
