import Foundation

/// Static placeholder content so the shell renders meaningfully before the
/// opencode networking layer is wired up.
enum SampleData {
    struct SessionRow: Identifiable {
        let id: String
        let title: String
        let project: String
        let branch: String
        let added: Int
        let removed: Int
        let relativeTime: String
        let active: Bool
    }

    static let sessions: [SessionRow] = [
        .init(id: "ses_1", title: "Manual save toggle in file editor toolbar", project: "Korbo", branch: "main", added: 4330, removed: 240, relativeTime: "1h", active: true),
        .init(id: "ses_2", title: "Improvement proxy for web dev tunnel", project: "Korbo", branch: "main", added: 88, removed: 12, relativeTime: "1m", active: false),
        .init(id: "ses_3", title: "Changelog unreleased bullet updates", project: "Korbo", branch: "main", added: 21, removed: 4, relativeTime: "3h", active: false),
        .init(id: "ses_4", title: "Review PR #1123: adding missing tests", project: "Korbo", branch: "review-pr-1123", added: 156, removed: 30, relativeTime: "3h", active: false),
        .init(id: "ses_5", title: "Git sidebar refactoring", project: "Korbo", branch: "main", added: 402, removed: 118, relativeTime: "7h", active: false),
    ]

    struct ChangeRow: Identifiable {
        let id = UUID()
        let path: String
        let status: String   // M / A / D / ?
        let added: Int
        let removed: Int
    }

    static let changes: [ChangeRow] = [
        .init(path: "Korbo/App/RootView.swift", status: "M", added: 1, removed: 92),
        .init(path: "Korbo/Features/Chat/ChatPane.swift", status: "?", added: 37, removed: 0),
        .init(path: "Korbo/Networking/OpencodeClient.swift", status: "?", added: 58, removed: 0),
        .init(path: "docs/PRD.md", status: "M", added: 74, removed: 0),
        .init(path: "project.yml", status: "M", added: 4, removed: 3),
    ]
}
