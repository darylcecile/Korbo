import SwiftUI

/// Top-level UI state for the shell. Networking/session state will hang off
/// this as the app is built out per the PRD.
@MainActor
final class AppModel: ObservableObject {
    @Published var showRightSidebar = true
    @Published var rightTab: RightTab = .git
    @Published var showConnectionSheet = false
    @Published var showSettingsSheet = false

    /// Command palette (⌘P / ⌘K) overlay.
    @Published var showCommandPalette = false

    /// The chat composer text, lifted here so the command palette (and future
    /// `@`/`/`/`!` autocomplete) can prefill it. `ChatPane` binds its TextField
    /// to this and clears it on send.
    @Published var composerDraft: String = ""
    /// Bumped to request keyboard focus on the composer; `ChatPane` observes it.
    @Published var focusComposerToken = 0

    func toggleCommandPalette() { showCommandPalette.toggle() }
    func focusComposer() { focusComposerToken &+= 1 }

    /// Reveal the right sidebar on a specific tab.
    func showRightTab(_ tab: RightTab) {
        rightTab = tab
        showRightSidebar = true
    }

    enum RightTab: String, CaseIterable, Identifiable {
        case git, files, terminal, context
        var id: String { rawValue }
        var title: String { rawValue }
        var systemImage: String {
            switch self {
            case .git: return "arrow.triangle.branch"
            case .files: return "folder"
            case .terminal: return "terminal"
            case .context: return "doc.text.magnifyingglass"
            }
        }
    }
}
