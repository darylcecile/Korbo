import Foundation

enum OpencodeError: LocalizedError {
    case invalidURL
    case http(status: Int, body: String)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server URL is not valid."
        case .http(let status, let body):
            let extra = body.isEmpty ? "" : " — \(body.prefix(200))"
            switch status {
            case 401: return "Authentication failed (401). Check your credentials.\(extra)"
            case 403: return "Access denied (403).\(extra)"
            case 404: return "Endpoint not found (404). Is this an opencode server?\(extra)"
            default:  return "Server returned HTTP \(status).\(extra)"
            }
        case .transport(let error):
            return "Could not reach the server: \(error.localizedDescription)"
        case .decoding(let error):
            return "Unexpected response from server: \(error.localizedDescription)"
        }
    }
}

/// Typed client for the opencode HTTP + SSE API. Stateless beyond its config;
/// safe to recreate when the selected server changes. The full surface is
/// documented in docs/OPENCODE_API.md.
actor OpencodeClient {
    let config: ServerConfig
    private let session: URLSession
    private let decoder: JSONDecoder

    init(config: ServerConfig, session: URLSession? = nil) {
        self.config = config
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 20
            cfg.waitsForConnectivity = false
            self.session = URLSession(configuration: cfg)
        }
        self.decoder = JSONDecoder()
    }

    // MARK: - Health & metadata

    /// `GET /global/health` — returns true on HTTP 200.
    func health() async throws -> Bool {
        let (_, response) = try await raw(.get, "/global/health")
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// `GET /session` — list sessions for the connected instance.
    func listSessions() async throws -> [OCSession] {
        try await getJSON("/session")
    }

    /// `GET /session/{id}` — fetch a single session.
    func getSession(_ id: String) async throws -> OCSession {
        try await getJSON("/session/\(id)")
    }

    /// `GET /session/{id}/message` — messages with their parts.
    func listMessages(sessionID: String) async throws -> [OCMessageItem] {
        try await getJSON("/session/\(sessionID)/message")
    }

    /// `GET /provider` — available providers & models.
    func listProviders() async throws -> OCProvidersResponse {
        try await getJSON("/provider")
    }

    /// `GET /agent` — configured agents.
    func listAgents() async throws -> [OCAgent] {
        try await getJSON("/agent")
    }

    /// `GET /command` — slash commands.
    func listCommands() async throws -> [OCCommand] {
        try await getJSON("/command")
    }

    // MARK: - Provider auth

    /// `PUT /auth/{providerID}` with `{ type: "api", key }` — store an API key for
    /// a provider so the server can connect to it. Returns whether it was accepted.
    @discardableResult
    func setProviderAPIKey(_ providerID: String, key: String) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: ["type": "api", "key": key])
        let (out, _) = try await raw(.put, "/auth/\(Self.queryEncode(providerID))", body: body)
        return (try? decoder.decode(Bool.self, from: out)) ?? true
    }

    /// `DELETE /auth/{providerID}` — remove stored credentials for a provider.
    @discardableResult
    func removeProviderAuth(_ providerID: String) async throws -> Bool {
        let (out, _) = try await raw(.delete, "/auth/\(Self.queryEncode(providerID))")
        return (try? decoder.decode(Bool.self, from: out)) ?? true
    }

    // MARK: - VCS / git

    /// `GET /vcs` — current branch + repository default branch.
    func vcsInfo() async throws -> OCVcsInfo {
        try await getJSON("/vcs")
    }

    /// `GET /vcs/diff?mode=git|branch` — per-file diffs (status, ±counts, patch).
    /// `git` = uncommitted working-tree changes; `branch` = this branch vs its base.
    func vcsDiff(mode: String) async throws -> [OCVcsFileDiff] {
        try await getJSON("/vcs/diff?mode=\(mode)")
    }

    // MARK: - Files (read-only)

    /// `GET /file?path=` — list one directory level of the workspace.
    func listFiles(path: String) async throws -> [OCFileNode] {
        try await getJSON("/file?path=\(Self.queryEncode(path))")
    }

    /// `GET /file/content?path=` — read a file's contents.
    func readFile(path: String) async throws -> OCFileContent {
        try await getJSON("/file/content?path=\(Self.queryEncode(path))")
    }

    /// `GET /find/file?query=` — fuzzy file-path search across the workspace.
    func findFiles(query: String, limit: Int = 100) async throws -> [String] {
        try await getJSON("/find/file?query=\(Self.queryEncode(query))&limit=\(limit)")
    }

    // MARK: - Terminal (PTY)

    /// `GET /pty/shells` — login shells the server can spawn.
    func listShells() async throws -> [OCShell] {
        try await getJSON("/pty/shells")
    }

    /// `GET /pty` — currently running PTY sessions.
    func listPtys() async throws -> [OCPty] {
        try await getJSON("/pty")
    }

    /// `POST /pty` — spawn a PTY. `command` defaults to the server's preferred shell.
    func createPty(command: String? = nil, cwd: String? = nil, title: String? = nil) async throws -> OCPty {
        var body: [String: Any] = [:]
        if let command { body["command"] = command }
        if let cwd { body["cwd"] = cwd }
        if let title { body["title"] = title }
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await postJSON("/pty", body: data)
    }

    /// `PUT /pty/{id}` with `{ size: { rows, cols } }` — resize the pseudo-terminal.
    @discardableResult
    func resizePty(_ id: String, rows: Int, cols: Int) async throws -> OCPty {
        let data = try JSONSerialization.data(withJSONObject: ["size": ["rows": rows, "cols": cols]])
        let (out, _) = try await raw(.put, "/pty/\(id)", body: data)
        do { return try decoder.decode(OCPty.self, from: out) }
        catch { throw OpencodeError.decoding(error) }
    }

    /// `DELETE /pty/{id}` — kill a PTY session.
    @discardableResult
    func killPty(_ id: String) async throws -> Bool {
        let (out, _) = try await raw(.delete, "/pty/\(id)")
        return (try? decoder.decode(Bool.self, from: out)) ?? true
    }

    /// WebSocket URL for live PTY I/O (`GET /pty/{id}/connect`). The server upgrades
    /// this to a socket carrying raw output as text frames and `0x00`+JSON control
    /// frames as binary; client writes raw stdin as text frames.
    nonisolated func ptyWebSocketURL(_ id: String) -> URL? {
        guard let http = makeURL("/pty/\(id)/connect") else { return nil }
        var s = http.absoluteString
        if s.hasPrefix("https://") { s = "wss://" + s.dropFirst("https://".count) }
        else if s.hasPrefix("http://") { s = "ws://" + s.dropFirst("http://".count) }
        return URL(string: s)
    }

    /// Auth/custom headers for the PTY WebSocket handshake.
    nonisolated func socketHeaders() -> [String: String] { config.authHeaders() }


    /// Percent-encode a query-string value. `makeURL` concatenates raw strings, so
    /// reserved characters (space, `&`, `+`, `=`, `#`, `%`, `?`) must be escaped here.
    nonisolated static func queryEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: " &+=#%?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Prompting

    /// `POST /session` — create a new session.
    func createSession(title: String? = nil) async throws -> OCSession {
        var body: [String: Any] = [:]
        if let title { body["title"] = title }
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await postJSON("/session", body: data)
    }

    /// `PATCH /session/{id}` with `{ title }` — rename a session.
    @discardableResult
    func updateSessionTitle(_ id: String, title: String) async throws -> OCSession {
        let data = try JSONSerialization.data(withJSONObject: ["title": title])
        let (out, _) = try await raw(.patch, "/session/\(id)", body: data)
        do { return try decoder.decode(OCSession.self, from: out) }
        catch { throw OpencodeError.decoding(error) }
    }

    /// `PATCH /session/{id}` with `{ time: { archived } }` — archive (non-zero
    /// timestamp) or unarchive (`0`) a session.
    @discardableResult
    func setSessionArchived(_ id: String, archived: Bool) async throws -> OCSession {
        let stamp = archived ? Int(Date().timeIntervalSince1970 * 1000) : 0
        let data = try JSONSerialization.data(withJSONObject: ["time": ["archived": stamp]])
        let (out, _) = try await raw(.patch, "/session/\(id)", body: data)
        do { return try decoder.decode(OCSession.self, from: out) }
        catch { throw OpencodeError.decoding(error) }
    }

    /// `DELETE /session/{id}` — permanently delete a session.
    func deleteSession(_ id: String) async throws {
        _ = try await raw(.delete, "/session/\(id)")
    }

    /// `POST /session/{id}/fork` — duplicate a session (optionally up to a
    /// specific `messageID`). Returns the new session (titled "… (fork #N)").
    func forkSession(_ id: String, messageID: String? = nil) async throws -> OCSession {
        var body: [String: Any] = [:]
        if let messageID { body["messageID"] = messageID }
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await postJSON("/session/\(id)/fork", body: data)
    }

    /// `POST /session/{id}/share` — publish a public share link. Returns the
    /// session with `share.url` populated.
    @discardableResult
    func shareSession(_ id: String) async throws -> OCSession {
        let (out, _) = try await raw(.post, "/session/\(id)/share")
        do { return try decoder.decode(OCSession.self, from: out) }
        catch { throw OpencodeError.decoding(error) }
    }

    /// `DELETE /session/{id}/share` — revoke the public share link.
    @discardableResult
    func unshareSession(_ id: String) async throws -> OCSession {
        let (out, _) = try await raw(.delete, "/session/\(id)/share")
        do { return try decoder.decode(OCSession.self, from: out) }
        catch { throw OpencodeError.decoding(error) }
    }

    /// `POST /session/{id}/command` — run a registered `/command` (with optional
    /// free-text `arguments`). The assistant reply streams over `/global/event`.
    func runCommand(sessionID: String, command: String, arguments: String?,
                    agent: String?, model: OCModelRef?) async throws {
        var body: [String: Any] = ["command": command]
        if let arguments, !arguments.isEmpty { body["arguments"] = arguments }
        if let agent { body["agent"] = agent }
        if let model { body["model"] = "\(model.providerID)/\(model.modelID)" }
        let data = try JSONSerialization.data(withJSONObject: body)
        _ = try await raw(.post, "/session/\(sessionID)/command", body: data)
    }

    /// `POST /session/{id}/prompt_async` — fire-and-forget; the reply streams over
    /// `GET /global/event` (and is also readable via `GET …/message`).
    func sendPromptAsync(sessionID: String, body: Data) async throws {
        _ = try await raw(.post, "/session/\(sessionID)/prompt_async", body: body)
    }

    /// `POST /session/{id}/abort` — stop the in-progress run for a session.
    func abort(sessionID: String) async throws {
        _ = try await raw(.post, "/session/\(sessionID)/abort")
    }

    /// `POST /session/{id}/summarize` — compact the conversation into a summary
    /// to reclaim context window. Requires a model to perform the summarization.
    /// Returns `true` when the server accepted the request.
    @discardableResult
    func summarize(sessionID: String, providerID: String, modelID: String, auto: Bool = false) async throws -> Bool {
        let data = try JSONSerialization.data(withJSONObject: [
            "providerID": providerID, "modelID": modelID, "auto": auto
        ])
        let out: Bool = try await postJSON("/session/\(sessionID)/summarize", body: data)
        return out
    }

    /// `POST /session/{id}/revert` — roll the session back to (and including)
    /// `messageID`, hiding everything from that point. Reversible via `unrevert`.
    /// Returns the updated session with its `revert` marker populated.
    @discardableResult
    func revert(sessionID: String, messageID: String, partID: String? = nil) async throws -> OCSession {
        var dict: [String: Any] = ["messageID": messageID]
        if let partID { dict["partID"] = partID }
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try await postJSON("/session/\(sessionID)/revert", body: data)
    }

    /// `POST /session/{id}/unrevert` — restore messages hidden by a prior
    /// `revert`. Returns the updated session with its `revert` marker cleared.
    @discardableResult
    func unrevert(sessionID: String) async throws -> OCSession {
        let (out, _) = try await raw(.post, "/session/\(sessionID)/unrevert")
        do { return try decoder.decode(OCSession.self, from: out) }
        catch { throw OpencodeError.decoding(error) }
    }

    /// `POST /session/{id}/permissions/{permissionID}` — reply to a permission
    /// request raised by a tool (`once` / `always` / `reject`).
    func replyPermission(sessionID: String, permissionID: String, response: String) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["response": response])
        _ = try await raw(.post, "/session/\(sessionID)/permissions/\(permissionID)", body: data)
    }

    /// `DELETE /session/{id}/message/{messageID}` — permanently remove a single
    /// message (and its parts) from the conversation.
    func deleteMessage(sessionID: String, messageID: String) async throws {
        _ = try await raw(.delete, "/session/\(sessionID)/message/\(messageID)")
    }

    /// `POST /question/{requestID}/reply` — answer a question the agent asked.
    /// `answers` is one array of selected option labels per question, in order.
    func replyQuestion(requestID: String, answers: [[String]]) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["answers": answers])
        _ = try await raw(.post, "/question/\(requestID)/reply", body: data)
    }

    /// `POST /question/{requestID}/reject` — dismiss a question without answering.
    func rejectQuestion(requestID: String) async throws {
        _ = try await raw(.post, "/question/\(requestID)/reject")
    }

    // MARK: - Event stream (SSE)

    /// Opens `GET /global/event` and yields decoded envelopes until the task is
    /// cancelled or the connection drops. Callers own reconnection/backoff.
    nonisolated func events() -> AsyncThrowingStream<OCEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = makeURL("/global/event") else { throw OpencodeError.invalidURL }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = .infinity
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    for (k, v) in config.authHeaders() { request.setValue(v, forHTTPHeaderField: k) }

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw OpencodeError.http(status: http.statusCode, body: "")
                    }

                    // opencode emits one complete JSON object per `data:` line and
                    // URLSession's AsyncBytes.lines does NOT yield the blank separator
                    // lines, so decode + dispatch on each data line directly.
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let value = line.dropFirst(5).drop(while: { $0 == " " })
                        if let data = String(value).data(using: .utf8),
                           let event = try? JSONDecoder().decode(OCEvent.self, from: data) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Transport

    enum Method: String { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE", put = "PUT" }

    private func getJSON<T: Decodable>(_ path: String) async throws -> T {
        let (data, _) = try await raw(.get, path)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw OpencodeError.decoding(error) }
    }

    private func postJSON<T: Decodable>(_ path: String, body: Data) async throws -> T {
        let (data, _) = try await raw(.post, path, body: body)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw OpencodeError.decoding(error) }
    }

    @discardableResult
    private func raw(_ method: Method, _ path: String, body: Data? = nil) async throws -> (Data, URLResponse) {
        guard let url = makeURL(path) else { throw OpencodeError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (k, v) in config.authHeaders() { request.setValue(v, forHTTPHeaderField: k) }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpencodeError.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpencodeError.http(status: http.statusCode, body: body)
        }
        return (data, response)
    }

    nonisolated private func makeURL(_ path: String) -> URL? {
        guard let base = config.baseURL else { return nil }
        return URL(string: base.absoluteString + path)
    }

    // MARK: - Provider authentication (OAuth / sign-in methods)

    /// `GET /provider/auth` — sign-in methods (OAuth / API key) keyed by provider id.
    func providerAuthMethods() async throws -> [String: [ProviderAuthMethod]] {
        try await getJSON("/provider/auth")
    }

    /// `POST /provider/{id}/oauth/authorize` — begin an OAuth/device flow.
    func oauthAuthorize(_ providerID: String, method: Int,
                        inputs: [String: String]) async throws -> ProviderAuthAuthorization {
        var payload: [String: Any] = ["method": method]
        if !inputs.isEmpty { payload["inputs"] = inputs }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await postJSON("/provider/\(providerID)/oauth/authorize", body: body)
    }

    /// `POST /provider/{id}/oauth/callback` — complete the flow. For `auto`
    /// (device) flows call repeatedly with no `code` until it returns `true`;
    /// for `code` flows pass the code the user pasted back.
    @discardableResult
    func oauthCallback(_ providerID: String, method: Int, code: String? = nil) async throws -> Bool {
        var payload: [String: Any] = ["method": method]
        if let code, !code.isEmpty { payload["code"] = code }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await raw(.post, "/provider/\(providerID)/oauth/callback", body: body)
        return (try? decoder.decode(Bool.self, from: data)) ?? false
    }
}
