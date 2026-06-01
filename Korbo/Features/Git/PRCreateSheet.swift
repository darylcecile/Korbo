import SwiftUI

/// "Create pull request" sheet. Walks the user through (1) mapping the active
/// opencode session directory to a GitHub repo (if it isn't yet) and (2)
/// filling in title / body / base / head / draft, then POSTs via
/// `GitHubStore.createPR`. Renders a success card with a link to the new PR.
struct PRCreateSheet: View {
    @EnvironmentObject var store: KorboStore
    @EnvironmentObject var github: GitHubStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL

    // Form state
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var base: String = ""
    @State private var head: String = ""
    @State private var draft: Bool = false
    @State private var didPrefill: Bool = false

    // Submission state
    @State private var submitting: Bool = false
    @State private var errorText: String?
    @State private var created: GHPullRequest?

    // Repo picker state
    @State private var repoQuery: String = ""

    private var directory: String? { store.selectedSession?.directory }
    private var mappedRepo: String? { github.repo(forDirectory: directory) }

    var body: some View {
        NavigationStack {
            Group {
                if !github.isSignedIn {
                    signedOutState
                } else if let pr = created {
                    successState(pr)
                } else if mappedRepo == nil {
                    repoPicker
                } else {
                    form
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("New Pull Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if created != nil {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Signed out

    private var signedOutState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text("Not signed in")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Sign in to GitHub in Settings to create pull requests.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
                .padding(.bottom, 16)
        }
        .padding(24)
    }

    // MARK: - Repo picker

    private var repoPicker: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pick a repository")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Link \(directory.map { displayPath($0) } ?? "this session") to a GitHub repo.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    TextField("Search repositories", text: $repoQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 13))
                }
                .padding(8)
                .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Divider().overlay(Theme.border)

            if github.isLoadingRepos && github.repos.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView().tint(Theme.textTertiary)
                    Text("Loading repositories…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredRepos.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text(github.repos.isEmpty ? "No repositories found." : "No matches.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Button {
                        Task { await github.loadRepos() }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredRepos) { repo in
                            Button {
                                github.setRepo(repo.fullName, forDirectory: directory)
                            } label: {
                                repoRow(repo)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(Theme.border)
                        }
                    }
                }
            }
        }
        .task {
            if github.repos.isEmpty {
                await github.loadRepos()
            }
        }
    }

    private var filteredRepos: [GHRepo] {
        let q = repoQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return github.repos }
        return github.repos.filter { $0.fullName.lowercased().contains(q) }
    }

    private func repoRow(_ repo: GHRepo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: repo.`private` ? "lock.fill" : "book.closed")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(repo.fullName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                    Text(mappedRepo ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change") {
                        github.setRepo(nil, forDirectory: directory)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.borderless)
                    .disabled(submitting)
                }
            }

            Section("Title") {
                TextField("Pull request title", text: $title)
                    .font(.system(size: 14))
                    .disabled(submitting)
            }

            Section("Description") {
                ZStack(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text("Describe what changed and why")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $bodyText)
                        .font(.system(size: 13))
                        .frame(minHeight: 120)
                        .disabled(submitting)
                        .scrollContentBackground(.hidden)
                }
            }

            Section("Branches") {
                LabeledContent {
                    TextField("base", text: $base)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 13, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .disabled(submitting)
                } label: {
                    Text("Base")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                LabeledContent {
                    TextField("head", text: $head)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 13, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .disabled(submitting)
                } label: {
                    Text("Head")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Toggle(isOn: $draft) {
                    Text("Create as draft")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                }
                .disabled(submitting)
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.removed)
                }
            }

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        if submitting { ProgressView().controlSize(.small) }
                        Text(submitting ? "Creating…" : "Create Pull Request")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear { prefillIfNeeded() }
    }

    private var canSubmit: Bool {
        !submitting &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !head.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func prefillIfNeeded() {
        guard !didPrefill else { return }
        didPrefill = true
        if title.isEmpty {
            title = store.vcsInfo?.branch ?? ""
        }
        if head.isEmpty {
            head = store.vcsInfo?.branch ?? ""
        }
        if base.isEmpty {
            base = store.vcsInfo?.defaultBranch ?? "main"
        }
    }

    private func submit() {
        guard let ownerRepo = github.ownerRepo(forDirectory: directory) else {
            errorText = "Pick a repository first."
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHead = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        errorText = nil
        submitting = true
        Task {
            defer { submitting = false }
            do {
                let pr = try await github.createPR(
                    owner: ownerRepo.owner,
                    repo: ownerRepo.repo,
                    title: trimmedTitle,
                    head: trimmedHead,
                    base: trimmedBase,
                    body: trimmedBody.isEmpty ? nil : trimmedBody,
                    draft: draft
                )
                created = pr
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    // MARK: - Success

    private func successState(_ pr: GHPullRequest) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Theme.added)
                .accessibilityHidden(true)
            Text("PR #\(pr.number) created")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(pr.title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let url = URL(string: pr.htmlURL) {
                Button {
                    openURL(url)
                } label: {
                    Label("Open on GitHub", systemImage: "arrow.up.right.square")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.top, 4)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .padding(.bottom, 16)
        }
        .padding(24)
    }

    // MARK: - Helpers

    private func displayPath(_ path: String) -> String {
        if let last = path.split(separator: "/").last { return String(last) }
        return path
    }
}
