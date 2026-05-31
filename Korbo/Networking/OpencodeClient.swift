import Foundation

/// Connection configuration for an opencode server.
///
/// `opencode serve` listens on `http://127.0.0.1:4096` by default and is
/// unauthenticated (localhost-by-design). For remote/iPad access the server is
/// either bound to the LAN (`--hostname 0.0.0.0` / mDNS) or, preferably, placed
/// behind a reverse proxy that terminates TLS and adds auth. `headers` carries
/// any bearer/basic credentials the proxy expects.
struct ServerConfig: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var baseURL: URL
    var headers: [String: String] = [:]

    static let localDefault = ServerConfig(
        name: "Local",
        baseURL: URL(string: "http://127.0.0.1:4096")!
    )
}

/// Minimal typed client for the opencode HTTP API. This is a skeleton: the full
/// surface (sessions, prompt, events SSE, permissions, git/vcs, files, pty…) is
/// documented in docs/OPENCODE_API.md and will be filled in per the PRD.
actor OpencodeClient {
    private let config: ServerConfig
    private let session: URLSession

    init(config: ServerConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// GET /global/health — quick reachability check.
    func health() async throws -> Bool {
        let (_, response) = try await send(.get, "/global/health")
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// GET /session — list sessions for the connected instance.
    func listSessions() async throws -> Data {
        try await send(.get, "/session").0
    }

    /// POST /session/{id}/prompt_async — fire-and-forget a prompt; stream the
    /// assistant response over GET /event.
    func sendPrompt(sessionID: String, body: Data) async throws {
        _ = try await send(.post, "/session/\(sessionID)/prompt_async", body: body)
    }

    // MARK: - Transport

    enum Method: String { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE", put = "PUT" }

    private func send(_ method: Method, _ path: String, body: Data? = nil) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
        request.httpMethod = method.rawValue
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (k, v) in config.headers { request.setValue(v, forHTTPHeaderField: k) }
        return try await session.data(for: request)
    }
}
