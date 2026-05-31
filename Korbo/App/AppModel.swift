import SwiftUI

/// Top-level UI state for the shell. Networking/session state will hang off
/// this as the app is built out per the PRD.
@MainActor
final class AppModel: ObservableObject {
    @Published var showRightSidebar = true
    @Published var rightTab: RightTab = .git
    @Published var selectedSessionID: String? = SampleData.sessions.first?.id

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
