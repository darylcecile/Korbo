import Foundation
import SwiftUI

/// Errors surfaced by `GitHubStore`'s PR helpers (distinct from the lower-level
/// `GitHubError` thrown by the networking actor).
enum GitHubStoreError: LocalizedError {
    case notSignedIn
    case noRepoSelected

    var errorDescription: String? {
        switch self {
        case .notSignedIn:   return "Sign in to GitHub first (Settings → GitHub)."
        case .noRepoSelected: return "Pick a repository for this session first."
        }
    }
}

/// UI-visible state for the in-progress GitHub device-flow sign-in.
struct DeviceFlowState: Equatable {
    let userCode: String
    let verificationURI: String
    let expiresAt: Date
    var polling: Bool
}

/// `@MainActor` ObservableObject backing the GitHub integration. Owns the
/// OAuth Client ID (a public app identifier, stored in UserDefaults), the
/// access token (stored in Keychain), the signed-in user, the repository
/// list, and the per-session-directory repo selection map. All networking
/// goes through the actor `GitHubClient`.
@MainActor
final class GitHubStore: ObservableObject {

    // MARK: Persisted keys
    private static let clientIDKey      = "github.clientID"
    private static let repoMapKey       = "github.repoByDirectory"
    private static let tokenAccount     = "github.oauth.token"
    private static let scope            = "repo"

    // MARK: Published state
    @Published var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: Self.clientIDKey) }
    }
    @Published private(set) var authedUser: GHUser?
    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var repos: [GHRepo] = []
    @Published private(set) var isLoadingRepos: Bool = false
    @Published var deviceFlow: DeviceFlowState?

    /// Map of opencode session `directory` → "owner/repo".
    @Published private(set) var repoByDirectory: [String: String] = [:]

    // MARK: Private
    private let client = GitHubClient()
    private var deviceFlowTask: Task<Void, Never>?

    /// Cached access token. Source of truth is the Keychain; this is a
    /// loaded-once mirror used by `token` and refreshed on sign-in/out.
    private var cachedToken: String?

    private var token: String? { cachedToken }

    // MARK: Init

    init() {
        let defaults = UserDefaults.standard
        self.clientID = defaults.string(forKey: Self.clientIDKey) ?? ""
        if let data = defaults.data(forKey: Self.repoMapKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.repoByDirectory = decoded
        }
        if let stored = Keychain.get(account: Self.tokenAccount), !stored.isEmpty {
            self.cachedToken = stored
            self.isSignedIn = true
            Task { await self.refreshCurrentUser() }
        }
    }

    // MARK: Public — repo map

    func repo(forDirectory directory: String?) -> String? {
        guard let directory, !directory.isEmpty else { return nil }
        return repoByDirectory[directory]
    }

    /// Split a stored `"owner/repo"` (for the given session directory) into its
    /// components, or `nil` if none is mapped / malformed.
    func ownerRepo(forDirectory directory: String?) -> (owner: String, repo: String)? {
        guard let full = repo(forDirectory: directory) else { return nil }
        return Self.splitOwnerRepo(full)
    }

    static func splitOwnerRepo(_ full: String) -> (owner: String, repo: String)? {
        let parts = full.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    // MARK: Public — pull requests

    /// Open a PR on `owner/repo`. Throws `GitHubStoreError.notSignedIn` if there
    /// is no token. Returns the created `GHPullRequest` (with `htmlURL`/`number`).
    func createPR(
        owner: String, repo: String, title: String,
        head: String, base: String, body: String?, draft: Bool
    ) async throws -> GHPullRequest {
        guard let token else { throw GitHubStoreError.notSignedIn }
        return try await client.createPullRequest(
            token: token, owner: owner, repo: repo,
            title: title, head: head, base: base, body: body, draft: draft
        )
    }

    /// List pull requests for `owner/repo` (`state` = "open" | "closed" | "all").
    func loadPullRequests(owner: String, repo: String, state: String) async throws -> [GHPullRequest] {
        guard let token else { throw GitHubStoreError.notSignedIn }
        return try await client.listPullRequests(token: token, owner: owner, repo: repo, state: state)
    }

    /// Reviews for a single PR.
    func loadReviews(owner: String, repo: String, number: Int) async throws -> [GHReview] {
        guard let token else { throw GitHubStoreError.notSignedIn }
        return try await client.listReviews(token: token, owner: owner, repo: repo, number: number)
    }

    /// Check-runs for a commit ref (e.g. a PR head SHA or branch name).
    func loadCheckRuns(owner: String, repo: String, ref: String) async throws -> [GHCheckRun] {
        guard let token else { throw GitHubStoreError.notSignedIn }
        return try await client.checkRuns(token: token, owner: owner, repo: repo, ref: ref)
    }

    /// Changed files (with per-file unified diffs) for a PR. Paginated server-side.
    func loadFiles(owner: String, repo: String, number: Int) async throws -> [GHPRFile] {
        guard let token else { throw GitHubStoreError.notSignedIn }
        var page = 1
        var collected: [GHPRFile] = []
        while true {
            let batch = try await client.listFiles(
                token: token, owner: owner, repo: repo, number: number, page: page
            )
            if batch.isEmpty { break }
            collected.append(contentsOf: batch)
            if batch.count < 100 { break }
            page += 1
            if page > 30 { break } // safety: at most 3000 files
        }
        return collected
    }

    /// Existing inline review comments for a PR.
    func loadReviewComments(owner: String, repo: String, number: Int) async throws -> [GHReviewComment] {
        guard let token else { throw GitHubStoreError.notSignedIn }
        return try await client.listReviewComments(token: token, owner: owner, repo: repo, number: number)
    }

    /// Add an inline review comment on a diff line.
    func addReviewComment(
        owner: String, repo: String, number: Int,
        body: String, commitID: String, path: String, line: Int, side: String
    ) async throws -> GHReviewComment {
        guard let token else { throw GitHubStoreError.notSignedIn }
        return try await client.createReviewComment(
            token: token, owner: owner, repo: repo, number: number,
            body: body, commitID: commitID, path: path, line: line, side: side
        )
    }

    /// Submit a review verdict (event = "COMMENT" | "APPROVE" | "REQUEST_CHANGES").
    func submitReview(
        owner: String, repo: String, number: Int, body: String?, event: String
    ) async throws -> GHReview {
        guard let token else { throw GitHubStoreError.notSignedIn }
        return try await client.submitReview(
            token: token, owner: owner, repo: repo, number: number, body: body, event: event
        )
    }

    /// Collaborators who can be requested as reviewers on `owner/repo`.
    func loadCollaborators(owner: String, repo: String) async throws -> [GHActor] {
        guard let token else { throw GitHubStoreError.notSignedIn }
        return try await client.listCollaborators(token: token, owner: owner, repo: repo)
    }

    /// Request reviews from the given GitHub logins.
    func requestReviewers(owner: String, repo: String, number: Int, reviewers: [String]) async throws {
        guard let token else { throw GitHubStoreError.notSignedIn }
        try await client.requestReviewers(
            token: token, owner: owner, repo: repo, number: number, reviewers: reviewers
        )
    }

    /// Merge a PR with the given method ("merge" | "squash" | "rebase").
    func mergePR(
        owner: String, repo: String, number: Int,
        method: String, commitTitle: String?, commitMessage: String?
    ) async throws -> GHMergeResult {
        guard let token else { throw GitHubStoreError.notSignedIn }
        return try await client.mergePullRequest(
            token: token, owner: owner, repo: repo, number: number,
            method: method, commitTitle: commitTitle, commitMessage: commitMessage
        )
    }

    func setRepo(_ ownerRepo: String?, forDirectory directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        if let ownerRepo, !ownerRepo.isEmpty {
            repoByDirectory[directory] = ownerRepo
        } else {
            repoByDirectory.removeValue(forKey: directory)
        }
        persistRepoMap()
    }

    private func persistRepoMap() {
        if let data = try? JSONEncoder().encode(repoByDirectory) {
            UserDefaults.standard.set(data, forKey: Self.repoMapKey)
        }
    }

    // MARK: Public — auth

    func signOut() {
        deviceFlowTask?.cancel()
        deviceFlowTask = nil
        deviceFlow = nil
        Keychain.delete(account: Self.tokenAccount)
        cachedToken = nil
        authedUser = nil
        repos = []
        isSignedIn = false
    }

    func cancelDeviceFlow() {
        deviceFlowTask?.cancel()
        deviceFlowTask = nil
        deviceFlow = nil
    }

    func startDeviceFlow() async {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        guard deviceFlow == nil else { return }

        let code: GHDeviceCode
        do {
            code = try await client.requestDeviceCode(clientID: id, scope: Self.scope)
        } catch {
            // Surface as a transient device-flow state so the sheet shows the
            // error briefly via the message field of GitHubError if needed.
            // (Foundation prints to stderr; UI agents can wire richer toasts.)
            print("GitHub device-flow start failed: \(error.localizedDescription)")
            return
        }

        let expires = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        deviceFlow = DeviceFlowState(
            userCode: code.userCode,
            verificationURI: code.verificationURI,
            expiresAt: expires,
            polling: true
        )

        deviceFlowTask = Task { [weak self] in
            await self?.pollLoop(clientID: id, deviceCode: code.deviceCode, interval: code.interval, expiresAt: expires)
        }
    }

    private func pollLoop(clientID: String, deviceCode: String, interval: Int, expiresAt: Date) async {
        var delay = max(interval, 1)
        while !Task.isCancelled {
            if Date() >= expiresAt {
                self.deviceFlow = nil
                self.deviceFlowTask = nil
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            if Task.isCancelled { return }

            let result: GHTokenPollResult
            do {
                result = try await client.pollAccessToken(clientID: clientID, deviceCode: deviceCode)
            } catch {
                print("GitHub device-flow poll failed: \(error.localizedDescription)")
                continue
            }
            switch result {
            case .pending:
                continue
            case .slowDown:
                delay += 5
            case .denied, .expired:
                self.deviceFlow = nil
                self.deviceFlowTask = nil
                return
            case .token(let token):
                Keychain.set(token, account: Self.tokenAccount)
                self.cachedToken = token
                self.isSignedIn = true
                self.deviceFlow = nil
                self.deviceFlowTask = nil
                await self.refreshCurrentUser()
                await self.loadRepos()
                return
            }
        }
    }

    private func refreshCurrentUser() async {
        guard let token else { return }
        do {
            self.authedUser = try await client.currentUser(token: token)
        } catch {
            print("GitHub currentUser failed: \(error.localizedDescription)")
        }
    }

    // MARK: Public — repos

    func loadRepos() async {
        guard let token else { return }
        isLoadingRepos = true
        defer { isLoadingRepos = false }
        var page = 1
        var collected: [GHRepo] = []
        while true {
            do {
                let batch = try await client.listRepositories(token: token, page: page)
                if batch.isEmpty { break }
                collected.append(contentsOf: batch)
                if batch.count < 100 { break }
                page += 1
                if page > 20 { break } // safety: at most 2000 repos
            } catch {
                print("GitHub listRepositories failed (page \(page)): \(error.localizedDescription)")
                break
            }
        }
        self.repos = collected
    }
}
