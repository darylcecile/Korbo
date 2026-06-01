import SwiftUI

/// Browse pull requests for the GitHub repository mapped to the current
/// opencode session directory. Tapping a PR opens a detail page with
/// reviews and CI check-runs for the head commit.
struct PRListView: View {
    @EnvironmentObject var store: KorboStore
    @EnvironmentObject var github: GitHubStore
    @Environment(\.dismiss) var dismiss

    @State private var stateFilter: PRStateFilter = .open
    @State private var prs: [GHPullRequest] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var repoSearch = ""

    var body: some View {
        NavigationStack {
            Group {
                if !github.isSignedIn {
                    notSignedInView
                } else if github.ownerRepo(forDirectory: store.selectedSession?.directory) == nil {
                    repoPickerView
                } else {
                    prListContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("Pull Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    // MARK: - Not signed in

    private var notSignedInView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text("Not signed in")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("Sign in to GitHub in Settings to view pull requests.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    // MARK: - Repo picker

    private var repoPickerView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pick a repository for this session")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if github.isLoadingRepos {
                    ProgressView().tint(Theme.textTertiary)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().overlay(Theme.border)

            if github.repos.isEmpty && !github.isLoadingRepos {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No repositories found.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Button("Reload") {
                        Task { await github.loadRepos() }
                    }
                    .foregroundStyle(Theme.accent)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredRepos) { repo in
                    Button {
                        github.setRepo(repo.fullName, forDirectory: store.selectedSession?.directory)
                    } label: {
                        HStack(spacing: 8) {
                            if repo.`private` {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary)
                                    .accessibilityHidden(true)
                            }
                            Text(repo.fullName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.panel)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
                .searchable(text: $repoSearch, placement: .navigationBarDrawer(displayMode: .always))
            }
        }
        .task {
            if github.repos.isEmpty { await github.loadRepos() }
        }
    }

    private var filteredRepos: [GHRepo] {
        let q = repoSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return github.repos }
        return github.repos.filter { $0.fullName.lowercased().contains(q) }
    }

    // MARK: - PR list

    private var prListContent: some View {
        let dir = store.selectedSession?.directory
        let mapped = github.repo(forDirectory: dir) ?? ""
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                    Text(mapped)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change") {
                        github.setRepo(nil, forDirectory: dir)
                        prs = []
                        errorText = nil
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                }

                Picker("State", selection: $stateFilter) {
                    ForEach(PRStateFilter.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(16)

            Divider().overlay(Theme.border)

            prListBody(dir: dir, mapped: mapped)
        }
        .task(id: TaskKey(repo: mapped, state: stateFilter)) {
            await reloadPRs(mapped: mapped)
        }
    }

    @ViewBuilder
    private func prListBody(dir: String?, mapped: String) -> some View {
        if loading && prs.isEmpty {
            VStack {
                Spacer()
                ProgressView().tint(Theme.textTertiary)
                Text("Loading pull requests…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 6)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorText {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.removed)
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.removed)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await reloadPRs(mapped: mapped) }
                }
                .foregroundStyle(Theme.accent)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if prs.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "tray")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.textTertiary)
                Text("No pull requests.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let ownerRepo = github.ownerRepo(forDirectory: dir) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(prs) { pr in
                        NavigationLink {
                            PRDetailView(pr: pr, owner: ownerRepo.owner, repo: ownerRepo.repo)
                                .environmentObject(github)
                        } label: {
                            PRRow(pr: pr)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Theme.border)
                    }
                }
            }
        }
    }

    private func reloadPRs(mapped: String) async {
        guard let ownerRepo = GitHubStore.splitOwnerRepo(mapped) else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            prs = try await github.loadPullRequests(
                owner: ownerRepo.owner, repo: ownerRepo.repo, state: stateFilter.apiValue
            )
        } catch {
            prs = []
            errorText = error.localizedDescription
        }
    }
}

// MARK: - State filter

private enum PRStateFilter: String, CaseIterable, Identifiable, Hashable {
    case open, closed, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: return "Open"
        case .closed: return "Closed"
        case .all: return "All"
        }
    }
    var apiValue: String { rawValue }
}

private struct TaskKey: Equatable, Hashable {
    let repo: String
    let state: PRStateFilter
}

// MARK: - PR row

private struct PRRow: View {
    let pr: GHPullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(pr.number)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Text(pr.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                PRStateBadge(state: pr.state, draft: pr.draft ?? false)
            }
            HStack(spacing: 8) {
                Text("@\(pr.user?.login ?? "?")")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(pr.base.ref) ← \(pr.head.ref)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - State badge

private struct PRStateBadge: View {
    let state: String
    let draft: Bool

    var body: some View {
        let (label, color): (String, Color) = {
            if draft { return ("Draft", Theme.textTertiary) }
            switch state.lowercased() {
            case "open":   return ("Open", Theme.added)
            case "closed": return ("Closed", Theme.removed)
            case "merged": return ("Merged", Theme.accent)
            default:       return (state.capitalized, Theme.textTertiary)
            }
        }()
        return Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Detail view

private struct PRDetailView: View {
    let pr: GHPullRequest
    let owner: String
    let repo: String

    @EnvironmentObject var github: GitHubStore

    @State private var reviews: [GHReview] = []
    @State private var loadingReviews = false
    @State private var reviewsError: String?

    @State private var checks: [GHCheckRun] = []
    @State private var loadingChecks = false
    @State private var checksError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                Divider().overlay(Theme.border)
                reviewsSection
                Divider().overlay(Theme.border)
                checksSection
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .navigationTitle("#\(pr.number)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadReviews()
        }
        .task {
            await loadChecks()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(pr.number)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                PRStateBadge(state: pr.state, draft: pr.draft ?? false)
                Spacer()
            }
            Text(pr.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 8) {
                Text("@\(pr.user?.login ?? "?")")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(pr.base.ref) ← \(pr.head.ref)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let url = URL(string: pr.htmlURL) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .medium))
                        Text("Open on GitHub")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    // MARK: Reviews

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reviews")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            if loadingReviews && reviews.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().tint(Theme.textTertiary).controlSize(.small)
                    Text("Loading reviews…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            } else if let err = reviewsError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.removed)
            } else if reviews.isEmpty {
                Text("No reviews yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(reviews) { review in
                        ReviewRow(review: review)
                        if review.id != reviews.last?.id {
                            Divider().overlay(Theme.border)
                        }
                    }
                }
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1)
                )
            }
        }
    }

    private func loadReviews() async {
        loadingReviews = true
        reviewsError = nil
        defer { loadingReviews = false }
        do {
            reviews = try await github.loadReviews(owner: owner, repo: repo, number: pr.number)
        } catch {
            reviews = []
            reviewsError = error.localizedDescription
        }
    }

    // MARK: Checks

    private var checksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Checks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if !checks.isEmpty {
                    Text(checksSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if loadingChecks && checks.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().tint(Theme.textTertiary).controlSize(.small)
                    Text("Loading checks…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            } else if let err = checksError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.removed)
            } else if checks.isEmpty {
                Text("No checks reported.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(checks) { check in
                        CheckRunRow(check: check)
                        if check.id != checks.last?.id {
                            Divider().overlay(Theme.border)
                        }
                    }
                }
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1)
                )
            }
        }
    }

    private var checksSummary: String {
        var passed = 0, failed = 0, running = 0, other = 0
        for c in checks {
            if c.status.lowercased() != "completed" {
                running += 1
                continue
            }
            switch (c.conclusion ?? "").lowercased() {
            case "success": passed += 1
            case "failure", "timed_out", "action_required": failed += 1
            default: other += 1
            }
        }
        var parts: [String] = []
        if passed > 0 { parts.append("\(passed) passed") }
        if failed > 0 { parts.append("\(failed) failing") }
        if running > 0 { parts.append("\(running) running") }
        if other > 0 { parts.append("\(other) other") }
        return parts.joined(separator: " · ")
    }

    private func loadChecks() async {
        loadingChecks = true
        checksError = nil
        defer { loadingChecks = false }
        let ref = pr.head.sha ?? pr.head.ref
        do {
            checks = try await github.loadCheckRuns(owner: owner, repo: repo, ref: ref)
        } catch {
            checks = []
            checksError = error.localizedDescription
        }
    }
}

// MARK: - Review row

private struct ReviewRow: View {
    let review: GHReview

    var body: some View {
        HStack(spacing: 10) {
            reviewIcon
                .frame(width: 18, height: 18)
            Text("@\(review.user?.login ?? "?")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            ReviewStateChip(state: review.state)
            Spacer()
            if let when = review.submittedAt {
                Text(relativeString(for: when))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var reviewIcon: some View {
        switch review.state.uppercased() {
        case "APPROVED":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.added)
        case "CHANGES_REQUESTED":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Theme.removed)
        case "COMMENTED":
            Image(systemName: "bubble.left.fill")
                .foregroundStyle(Theme.textTertiary)
        case "DISMISSED":
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(Theme.textTertiary)
        case "PENDING":
            Image(systemName: "clock")
                .foregroundStyle(Theme.textTertiary)
        default:
            Image(systemName: "circle")
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func relativeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct ReviewStateChip: View {
    let state: String

    var body: some View {
        let (label, color): (String, Color) = {
            switch state.uppercased() {
            case "APPROVED": return ("Approved", Theme.added)
            case "CHANGES_REQUESTED": return ("Changes requested", Theme.removed)
            case "COMMENTED": return ("Commented", Theme.textTertiary)
            case "DISMISSED": return ("Dismissed", Theme.textTertiary)
            case "PENDING": return ("Pending", Theme.textTertiary)
            default: return (state.capitalized, Theme.textTertiary)
            }
        }()
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Check-run row

private struct CheckRunRow: View {
    let check: GHCheckRun

    var body: some View {
        HStack(spacing: 10) {
            checkIcon
                .frame(width: 18, height: 18)
            Text(check.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(statusLabel)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var checkIcon: some View {
        if check.status.lowercased() != "completed" {
            ProgressView()
                .tint(Theme.accent)
                .controlSize(.small)
        } else {
            switch (check.conclusion ?? "").lowercased() {
            case "success":
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.added)
            case "failure", "timed_out", "action_required":
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.removed)
            case "neutral", "skipped", "cancelled":
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Theme.textTertiary)
            default:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var statusLabel: String {
        if check.status.lowercased() != "completed" {
            return check.status.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if let c = check.conclusion, !c.isEmpty {
            return c.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return "Completed"
    }
}
