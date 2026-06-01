import Foundation

enum GitHubError: LocalizedError {
    case invalidURL
    case http(status: Int, body: String)
    case transport(Error)
    case decoding(Error)
    case deviceFlow(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The GitHub URL is not valid."
        case .http(let status, let body):
            let extra = body.isEmpty ? "" : " — \(body.prefix(200))"
            switch status {
            case 401: return "GitHub authentication failed (401).\(extra)"
            case 403: return "GitHub denied the request (403).\(extra)"
            case 404: return "GitHub resource not found (404).\(extra)"
            case 422: return "GitHub rejected the request (422).\(extra)"
            default:  return "GitHub returned HTTP \(status).\(extra)"
            }
        case .transport(let error):
            return "Could not reach GitHub: \(error.localizedDescription)"
        case .decoding(let error):
            return "Unexpected response from GitHub: \(error.localizedDescription)"
        case .deviceFlow(let message):
            return message
        }
    }
}

// MARK: - Models

struct GHDeviceCode: Codable, Hashable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct GHUser: Codable, Hashable, Identifiable {
    let login: String
    let name: String?
    let avatarURL: String?

    var id: String { login }

    enum CodingKeys: String, CodingKey {
        case login, name
        case avatarURL = "avatar_url"
    }
}

struct GHRepoOwner: Codable, Hashable {
    let login: String
}

struct GHRepo: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let fullName: String
    let owner: GHRepoOwner
    let defaultBranch: String?
    let `private`: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, owner
        case fullName = "full_name"
        case defaultBranch = "default_branch"
        case `private`
    }
}

struct GHRef: Codable, Hashable {
    let ref: String
    let sha: String?
}

struct GHActor: Codable, Hashable {
    let login: String
}

struct GHPullRequest: Codable, Hashable, Identifiable {
    let number: Int
    let title: String
    let state: String
    let htmlURL: String
    let draft: Bool?
    let user: GHActor?
    let head: GHRef
    let base: GHRef

    var id: Int { number }

    enum CodingKeys: String, CodingKey {
        case number, title, state, draft, user, head, base
        case htmlURL = "html_url"
    }
}

struct GHReview: Codable, Hashable, Identifiable {
    let id: Int
    let state: String
    let user: GHActor?
    let submittedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, state, user
        case submittedAt = "submitted_at"
    }
}

struct GHCheckRun: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
}

/// A single file changed by a pull request (`GET /pulls/{n}/files`). `patch`
/// is the unified diff for that file (absent for binary/too-large files).
struct GHPRFile: Codable, Hashable, Identifiable {
    let filename: String
    let status: String
    let additions: Int
    let deletions: Int
    let changes: Int
    let patch: String?
    let sha: String?
    let blobURL: String?

    var id: String { sha.map { "\(filename)@\($0)" } ?? filename }

    enum CodingKeys: String, CodingKey {
        case filename, status, additions, deletions, changes, patch, sha
        case blobURL = "blob_url"
    }
}

/// An inline pull-request review comment anchored to a diff line
/// (`GET/POST /pulls/{n}/comments`).
struct GHReviewComment: Codable, Hashable, Identifiable {
    let id: Int
    let path: String?
    let line: Int?
    let originalLine: Int?
    let side: String?
    let body: String
    let user: GHActor?
    let diffHunk: String?
    let htmlURL: String?
    let createdAt: Date?
    let inReplyToID: Int?

    enum CodingKeys: String, CodingKey {
        case id, path, line, side, body, user
        case originalLine = "original_line"
        case diffHunk = "diff_hunk"
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case inReplyToID = "in_reply_to_id"
    }
}

private struct GHCheckRunsResponse: Codable {
    let checkRuns: [GHCheckRun]
    enum CodingKeys: String, CodingKey { case checkRuns = "check_runs" }
}

private struct GHTokenResponse: Codable {
    let accessToken: String?
    let tokenType: String?
    let scope: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope, error
        case errorDescription = "error_description"
    }
}

enum GHTokenPollResult {
    case pending
    case slowDown
    case denied
    case expired
    case token(String)
}

/// Typed client for GitHub's REST API + OAuth Device Flow. Mirrors
/// `OpencodeClient` in style. Token is passed per-call so the actor can be
/// shared across users / sign-outs without rebuilding.
actor GitHubClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let restHost = "https://api.github.com"
    private let webHost = "https://github.com"

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 20
            cfg.waitsForConnectivity = false
            self.session = URLSession(configuration: cfg)
        }
        let d = JSONDecoder()
        // Parse GitHub timestamps without capturing a mutable, non-Sendable
        // formatter in the (`@Sendable`) decoding closure: build fresh
        // formatters inside the closure for both fractional and plain seconds.
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: s) { return date }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date: \(s)")
        }
        self.decoder = d
    }

    // MARK: - Device flow

    /// `POST https://github.com/login/device/code`
    func requestDeviceCode(clientID: String, scope: String) async throws -> GHDeviceCode {
        let body = formBody(["client_id": clientID, "scope": scope])
        let (data, _) = try await raw(
            .post,
            url: webHost + "/login/device/code",
            body: body,
            contentType: "application/x-www-form-urlencoded",
            accept: "application/json",
            bearer: nil
        )
        do { return try decoder.decode(GHDeviceCode.self, from: data) }
        catch { throw GitHubError.decoding(error) }
    }

    /// `POST https://github.com/login/oauth/access_token` — returns one poll result.
    func pollAccessToken(clientID: String, deviceCode: String) async throws -> GHTokenPollResult {
        let body = formBody([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ])
        let (data, _) = try await raw(
            .post,
            url: webHost + "/login/oauth/access_token",
            body: body,
            contentType: "application/x-www-form-urlencoded",
            accept: "application/json",
            bearer: nil
        )
        let resp: GHTokenResponse
        do { resp = try decoder.decode(GHTokenResponse.self, from: data) }
        catch { throw GitHubError.decoding(error) }
        if let token = resp.accessToken, !token.isEmpty {
            return .token(token)
        }
        switch resp.error {
        case "authorization_pending": return .pending
        case "slow_down":              return .slowDown
        case "access_denied":          return .denied
        case "expired_token":          return .expired
        case let other?:
            throw GitHubError.deviceFlow(resp.errorDescription ?? other)
        case nil:
            throw GitHubError.deviceFlow("Empty response from GitHub token endpoint.")
        }
    }

    // MARK: - REST

    /// `GET /user`
    func currentUser(token: String) async throws -> GHUser {
        try await getJSON("/user", token: token)
    }

    /// `GET /user/repos` — paginated; caller loops until empty.
    func listRepositories(token: String, page: Int) async throws -> [GHRepo] {
        let path = "/user/repos?per_page=100&sort=updated"
            + "&affiliation=owner,collaborator,organization_member"
            + "&page=\(page)"
        return try await getJSON(path, token: token)
    }

    /// `POST /repos/{owner}/{repo}/pulls`
    func createPullRequest(
        token: String,
        owner: String,
        repo: String,
        title: String,
        head: String,
        base: String,
        body: String?,
        draft: Bool
    ) async throws -> GHPullRequest {
        var dict: [String: Any] = [
            "title": title, "head": head, "base": base, "draft": draft
        ]
        if let body, !body.isEmpty { dict["body"] = body }
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try await postJSON(
            "/repos/\(Self.pathEncode(owner))/\(Self.pathEncode(repo))/pulls",
            body: data, token: token
        )
    }

    /// `GET /repos/{owner}/{repo}/pulls?state=…`
    func listPullRequests(
        token: String, owner: String, repo: String, state: String
    ) async throws -> [GHPullRequest] {
        try await getJSON(
            "/repos/\(Self.pathEncode(owner))/\(Self.pathEncode(repo))/pulls?state=\(state)&per_page=50",
            token: token
        )
    }

    /// `GET /repos/{owner}/{repo}/pulls/{n}/reviews`
    func listReviews(
        token: String, owner: String, repo: String, number: Int
    ) async throws -> [GHReview] {
        try await getJSON(
            "/repos/\(Self.pathEncode(owner))/\(Self.pathEncode(repo))/pulls/\(number)/reviews",
            token: token
        )
    }

    /// `GET /repos/{owner}/{repo}/commits/{ref}/check-runs` — returns the
    /// `check_runs` array unwrapped.
    func checkRuns(
        token: String, owner: String, repo: String, ref: String
    ) async throws -> [GHCheckRun] {
        let wrapped: GHCheckRunsResponse = try await getJSON(
            "/repos/\(Self.pathEncode(owner))/\(Self.pathEncode(repo))/commits/\(Self.pathEncode(ref))/check-runs",
            token: token
        )
        return wrapped.checkRuns
    }

    /// `GET /repos/{owner}/{repo}/pulls/{n}/files` — paginated; caller loops.
    func listFiles(
        token: String, owner: String, repo: String, number: Int, page: Int
    ) async throws -> [GHPRFile] {
        try await getJSON(
            "/repos/\(Self.pathEncode(owner))/\(Self.pathEncode(repo))/pulls/\(number)/files?per_page=100&page=\(page)",
            token: token
        )
    }

    /// `GET /repos/{owner}/{repo}/pulls/{n}/comments` — inline review comments.
    func listReviewComments(
        token: String, owner: String, repo: String, number: Int
    ) async throws -> [GHReviewComment] {
        try await getJSON(
            "/repos/\(Self.pathEncode(owner))/\(Self.pathEncode(repo))/pulls/\(number)/comments?per_page=100",
            token: token
        )
    }

    /// `POST /repos/{owner}/{repo}/pulls/{n}/comments` — add an inline comment
    /// anchored to `path`/`line` on the given `side` ("RIGHT" | "LEFT") of the
    /// diff for commit `commitID` (the PR head SHA).
    func createReviewComment(
        token: String, owner: String, repo: String, number: Int,
        body: String, commitID: String, path: String, line: Int, side: String
    ) async throws -> GHReviewComment {
        let dict: [String: Any] = [
            "body": body, "commit_id": commitID,
            "path": path, "line": line, "side": side
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try await postJSON(
            "/repos/\(Self.pathEncode(owner))/\(Self.pathEncode(repo))/pulls/\(number)/comments",
            body: data, token: token
        )
    }

    /// `POST /repos/{owner}/{repo}/pulls/{n}/reviews` — submit a review with a
    /// verdict. `event` is "COMMENT" | "APPROVE" | "REQUEST_CHANGES".
    func submitReview(
        token: String, owner: String, repo: String, number: Int,
        body: String?, event: String
    ) async throws -> GHReview {
        var dict: [String: Any] = ["event": event]
        if let body, !body.isEmpty { dict["body"] = body }
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try await postJSON(
            "/repos/\(Self.pathEncode(owner))/\(Self.pathEncode(repo))/pulls/\(number)/reviews",
            body: data, token: token
        )
    }

    // MARK: - Transport

    enum Method: String { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE", put = "PUT" }

    private func getJSON<T: Decodable>(_ path: String, token: String) async throws -> T {
        let (data, _) = try await raw(.get, url: restHost + path, body: nil,
                                      contentType: nil,
                                      accept: "application/vnd.github+json",
                                      bearer: token)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw GitHubError.decoding(error) }
    }

    private func postJSON<T: Decodable>(_ path: String, body: Data, token: String) async throws -> T {
        let (data, _) = try await raw(.post, url: restHost + path, body: body,
                                      contentType: "application/json",
                                      accept: "application/vnd.github+json",
                                      bearer: token)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw GitHubError.decoding(error) }
    }

    @discardableResult
    private func raw(
        _ method: Method,
        url urlString: String,
        body: Data?,
        contentType: String?,
        accept: String,
        bearer: String?
    ) async throws -> (Data, URLResponse) {
        guard let url = URL(string: urlString) else { throw GitHubError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if urlString.hasPrefix(restHost) {
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        }
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubError.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.http(status: http.statusCode, body: body)
        }
        return (data, response)
    }

    private func formBody(_ params: [String: String]) -> Data {
        let pairs = params.map { k, v in
            "\(Self.formEncode(k))=\(Self.formEncode(v))"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    nonisolated static func pathEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    nonisolated static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: " &+=#%?/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
