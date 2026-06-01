import SwiftUI

/// Top-level UI state for the shell. Networking/session state will hang off
/// this as the app is built out per the PRD.
@MainActor
final class AppModel: ObservableObject {
    @Published var showRightSidebar = true
    @Published var rightTab: RightTab = .git
    @Published var showConnectionSheet = false
    @Published var showSettingsSheet = false

    /// Which view occupies the wide center column. The terminal and file viewer
    /// both live in the centre pane (toggled from toolbar/actions) so they get
    /// real width — and the right sidebar can still be collapsed to widen them.
    @Published var centerPane: CenterPane = .chat

    /// Computed bool for backward compatibility with existing terminal checks.
    var showTerminal: Bool { centerPane == .terminal }

    /// Computed bool: true when the file viewer is in the center pane.
    var showFileViewer: Bool { centerPane == .files }

    /// Command palette (⌘P / ⌘K) overlay.
    @Published var showCommandPalette = false

    /// The chat composer text, lifted here so the command palette (and future
    /// `@`/`/`/`!` autocomplete) can prefill it. `ChatPane` binds its TextField
    /// to this and clears it on send.
    @Published var composerDraft: String = "" {
        didSet { drafts[currentDraftSessionID ?? Self.noSessionDraftKey] = composerDraft }
    }
    /// Bumped to request keyboard focus on the composer; `ChatPane` observes it.
    @Published var focusComposerToken = 0

    // MARK: Per-session composer drafts

    /// Unsent composer text kept per session so switching sessions never loses or
    /// leaks a draft. Persisted to `UserDefaults` so drafts survive relaunches.
    private var drafts: [String: String] = AppModel.loadDrafts()
    /// The session whose draft `composerDraft` currently mirrors (`nil` → no
    /// session selected; stored under `noSessionDraftKey`).
    private var currentDraftSessionID: String?
    private static let draftsKey = "korbo.composerDrafts"
    private static let noSessionDraftKey = "__none__"

    /// Swap the live `composerDraft` to the given session's stored draft, saving
    /// the outgoing session's text first. Call when the selected session changes.
    func bindDraft(to sessionID: String?) {
        let key = sessionID ?? Self.noSessionDraftKey
        guard key != (currentDraftSessionID ?? Self.noSessionDraftKey) || currentDraftSessionID == nil else { return }
        currentDraftSessionID = sessionID
        // Assigning re-triggers `didSet`, but it writes the same value back under
        // the same key, so the map stays consistent.
        composerDraft = drafts[key] ?? ""
        persistDrafts()
    }

    /// Drop a session's stored draft (e.g. after a successful send) and clear the
    /// live field if it belongs to that session.
    func clearDraft(for sessionID: String?) {
        let key = sessionID ?? Self.noSessionDraftKey
        drafts[key] = nil
        if (currentDraftSessionID ?? Self.noSessionDraftKey) == key { composerDraft = "" }
        persistDrafts()
    }

    /// Persist the draft map. Cheap (small string dict); called on session switch,
    /// send, and app background rather than on every keystroke.
    func persistDrafts() {
        var pruned = drafts
        for (k, v) in pruned where v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pruned[k] = nil }
        drafts = pruned
        if let data = try? JSONEncoder().encode(pruned) {
            UserDefaults.standard.set(data, forKey: Self.draftsKey)
        }
    }

    private static func loadDrafts() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: draftsKey),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    /// Width-derived layout mode (drives adaptive 3/2/1-pane shell for Split View
    /// and Stage Manager). Updated by `RootView` from a `GeometryReader`.
    @Published var layoutMode: LayoutMode = .wide
    /// In compact mode the sessions sidebar is presented as an overlay drawer
    /// rather than inline; this controls its visibility.
    @Published var sessionsDrawerOpen = false

    /// User-adjustable widths for the inline side panes (drag the dividers).
    /// Persisted across launches; clamped on every change.
    @Published var sessionsPaneWidth: CGFloat = AppModel.loadWidth(sessionsWidthKey, fallback: 300)
    @Published var contextPaneWidth: CGFloat = AppModel.loadWidth(contextWidthKey, fallback: 420)

    static let sessionsWidthRange: ClosedRange<CGFloat> = 240...460
    static let contextWidthRange: ClosedRange<CGFloat> = 300...760
    private static let sessionsWidthKey = "korbo.sessionsPaneWidth"
    private static let contextWidthKey = "korbo.contextPaneWidth"

    private static func loadWidth(_ key: String, fallback: CGFloat) -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: key)
        return stored > 0 ? CGFloat(stored) : fallback
    }

    /// Adjust the sessions pane width by `delta` points, clamped and persisted.
    func resizeSessionsPane(by delta: CGFloat) {
        let next = (sessionsPaneWidth + delta)
            .clamped(to: Self.sessionsWidthRange)
        guard next != sessionsPaneWidth else { return }
        sessionsPaneWidth = next
        UserDefaults.standard.set(Double(next), forKey: Self.sessionsWidthKey)
    }

    /// Adjust the context pane width by `delta` points. The upper bound also
    /// respects the available window width so the pane never crowds out the chat.
    func resizeContextPane(by delta: CGFloat, available: CGFloat) {
        let upper = min(Self.contextWidthRange.upperBound, max(Self.contextWidthRange.lowerBound, available * 0.6))
        let next = (contextPaneWidth + delta)
            .clamped(to: Self.contextWidthRange.lowerBound...upper)
        guard next != contextPaneWidth else { return }
        contextPaneWidth = next
        UserDefaults.standard.set(Double(next), forKey: Self.contextWidthKey)
    }

    func toggleCommandPalette() { showCommandPalette.toggle() }
    func toggleTerminal() {
        centerPane = centerPane == .terminal ? .chat : .terminal
    }
    func showFilesCenter() { centerPane = .files }
    func showChat() { centerPane = .chat }
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

    /// Which pane is shown in the wide centre column.
    enum CenterPane {
        case chat, terminal, files
    }
}

extension Comparable {
    /// Clamp a value into a closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
