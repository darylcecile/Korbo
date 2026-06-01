import SwiftUI

/// Sheet for requesting reviews from repository collaborators on a PR
/// (`POST /pulls/{n}/requested_reviewers`).
struct PRReviewersSheet: View {
    let owner: String
    let repo: String
    let number: Int
    let excludeLogins: Set<String>
    let onDone: () -> Void

    @EnvironmentObject var github: GitHubStore
    @Environment(\.dismiss) private var dismiss

    @State private var collaborators: [GHActor] = []
    @State private var selected: Set<String> = []
    @State private var loading = false
    @State private var submitting = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading && collaborators.isEmpty {
                    centeredProgress("Loading collaborators…")
                } else if candidates.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("Request reviewers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if submitting { ProgressView().controlSize(.small) }
                        else { Text("Request").fontWeight(.semibold) }
                    }
                    .foregroundStyle(Theme.accent)
                    .disabled(selected.isEmpty || submitting)
                }
            }
            .task { await load() }
        }
    }

    private var candidates: [GHActor] {
        collaborators.filter { !excludeLogins.contains($0.login.lowercased()) }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let errorText {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.removed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                ForEach(candidates, id: \.login) { user in
                    Button { toggle(user.login) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected.contains(user.login) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(user.login) ? Theme.accent : Theme.textTertiary)
                            Text("@\(user.login)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Theme.border)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 24))
                .foregroundStyle(Theme.textTertiary)
            Text("No other collaborators to request.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let errorText {
                Text(errorText).font(.system(size: 12)).foregroundStyle(Theme.removed)
            }
        }
        .padding(24)
    }

    private func centeredProgress(_ label: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().tint(Theme.accent)
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
        }
    }

    private func toggle(_ login: String) {
        if selected.contains(login) { selected.remove(login) } else { selected.insert(login) }
    }

    private func load() async {
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            collaborators = try await github.loadCollaborators(owner: owner, repo: repo)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func submit() async {
        submitting = true
        errorText = nil
        defer { submitting = false }
        do {
            try await github.requestReviewers(
                owner: owner, repo: repo, number: number, reviewers: Array(selected)
            )
            onDone()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Sheet for merging a PR with a chosen method (`PUT /pulls/{n}/merge`).
struct PRMergeSheet: View {
    let pr: GHPullRequest
    let owner: String
    let repo: String
    let onMerged: (GHMergeResult) -> Void

    @EnvironmentObject var github: GitHubStore
    @Environment(\.dismiss) private var dismiss

    @State private var method: MergeMethod = .merge
    @State private var submitting = false
    @State private var errorText: String?

    enum MergeMethod: String, CaseIterable, Identifiable {
        case merge, squash, rebase
        var id: String { rawValue }
        var label: String {
            switch self {
            case .merge: return "Merge commit"
            case .squash: return "Squash"
            case .rebase: return "Rebase"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pr.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(pr.base.ref) ← \(pr.head.ref)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1).truncationMode(.middle)
                }

                Text("Method")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Picker("Method", selection: $method) {
                    ForEach(MergeMethod.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)

                Text("This merges \(pr.head.ref) into \(pr.base.ref) on GitHub. This cannot be undone from the app.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.removed)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()

                Button {
                    Task { await merge() }
                } label: {
                    HStack {
                        Spacer()
                        if submitting { ProgressView().controlSize(.small).tint(.white) }
                        else {
                            Image(systemName: "arrow.triangle.merge")
                            Text("\(method.label) and merge").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                }
                .disabled(submitting)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("Merge #\(pr.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func merge() async {
        submitting = true
        errorText = nil
        defer { submitting = false }
        do {
            let result = try await github.mergePR(
                owner: owner, repo: repo, number: pr.number,
                method: method.rawValue, commitTitle: nil, commitMessage: nil
            )
            if result.merged {
                onMerged(result)
                dismiss()
            } else {
                errorText = result.message
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
