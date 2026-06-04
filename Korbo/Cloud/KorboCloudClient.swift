import Foundation

/// Typed client for the Korbo Cloud management API (`my.korbo.app/api/...`).
/// Mirrors `GitHubClient` in style. The bearer token is read on demand through
/// `tokenProvider` so the actor always uses the current account token without
/// being rebuilt across sign-ins.
actor KorboCloudClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let tokenProvider: @Sendable () -> String?

    init(session: URLSession? = nil, tokenProvider: @escaping @Sendable () -> String?) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 20
            cfg.waitsForConnectivity = false
            self.session = URLSession(configuration: cfg)
        }
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.tokenProvider = tokenProvider
    }

    // MARK: - Public API

    /// `GET /api/me`
    func me() async throws -> CloudMeResponse {
        try await request("/api/me", method: .get)
    }

    /// `GET /api/instances`
    func listInstances() async throws -> [CloudInstance] {
        let response: CloudInstancesResponse = try await request("/api/instances", method: .get)
        return response.instances
    }

    /// `POST /api/instances` — provisions a new instance (HTTP 202).
    func createInstance(machineType: String, repo: String?) async throws -> CloudInstance {
        let body = CreateInstanceBody(machineType: machineType, repo: repo)
        let response: CloudInstanceResponse = try await request("/api/instances", method: .post, body: body)
        return response.instance
    }

    /// `GET /api/instances/:id`
    func getInstance(_ id: String) async throws -> CloudInstance {
        let response: CloudInstanceResponse = try await request("/api/instances/\(pathEncode(id))", method: .get)
        return response.instance
    }

    /// `GET /api/instances/:id/state`
    func instanceState(_ id: String) async throws -> CloudInstanceStateDetail {
        try await request("/api/instances/\(pathEncode(id))/state", method: .get)
    }

    /// `DELETE /api/instances/:id`
    func deleteInstance(_ id: String) async throws {
        let _: CloudOKResponse = try await request("/api/instances/\(pathEncode(id))", method: .delete)
    }

    /// `GET /api/github/installations`
    func installations() async throws -> [CloudInstallation] {
        let response: CloudInstallationsResponse = try await request("/api/github/installations", method: .get)
        return response.installations
    }

    /// `GET /api/github/repos?installationId=<n>`
    func repos(installationId: Int) async throws -> [CloudRepo] {
        let response: CloudReposResponse = try await request(
            "/api/github/repos?installationId=\(installationId)", method: .get
        )
        return response.repositories
    }

    /// `POST /api/credits/topup` — returns a checkout URL.
    func topupURL(credits: Int) async throws -> URL {
        let response: CloudTopupResponse = try await request(
            "/api/credits/topup", method: .post, body: TopupBody(credits: credits)
        )
        guard let url = URL(string: response.url) else {
            throw CloudError.http(200, "Malformed top-up URL: \(response.url)")
        }
        return url
    }

    /// `POST /api/auth/logout`
    func logout() async throws {
        let _: CloudOKResponse = try await request("/api/auth/logout", method: .post)
    }

    // MARK: - Request bodies

    private struct CreateInstanceBody: Encodable {
        let machineType: String
        let repo: String?
    }

    private struct TopupBody: Encodable {
        let credits: Int
    }

    // MARK: - Transport

    enum Method: String { case get = "GET", post = "POST", delete = "DELETE", put = "PUT", patch = "PATCH" }

    /// Builds a request against the dashboard base URL, attaches the bearer
    /// token, and decodes `T` on success. On non-2xx it decodes the backend
    /// error envelope (falling back to `CloudError.http`), mapping 401 to
    /// `CloudError.invalidToken`.
    private func request<T: Decodable>(
        _ path: String,
        method: Method,
        body: (any Encodable)? = nil
    ) async throws -> T {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw CloudError.notSignedIn
        }
        guard let url = URL(string: path, relativeTo: CloudConfig.dashboardBaseURL) else {
            throw CloudError.http(0, "Invalid path: \(path)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw CloudError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 { throw CloudError.invalidToken }
            if let envelope = try? decoder.decode(CloudErrorEnvelope.self, from: data) {
                let payload = envelope.error
                throw CloudError.envelope(
                    code: payload.code,
                    message: payload.message,
                    httpStatus: payload.httpStatus ?? status,
                    retryable: payload.retryable ?? false,
                    retryAfterSeconds: payload.retryAfterSeconds,
                    instanceId: payload.instanceId
                )
            }
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw CloudError.http(status, bodyString)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CloudError.http(status, "Unexpected response: \(error.localizedDescription)")
        }
    }

    private nonisolated func pathEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// Type-erasing wrapper so a heterogeneous `any Encodable` body can be encoded.
private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        encodeClosure = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
