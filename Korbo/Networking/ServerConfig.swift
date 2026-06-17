import Foundation
import Combine

/// How Korbo authenticates to a server. opencode itself is unauthenticated, so
/// remote deployments sit behind a reverse proxy / tunnel that adds auth. Basic
/// auth is the day-one mode for korbo.app; bearer is supported for the future
/// hosted backend.
enum AuthKind: String, Codable, CaseIterable, Identifiable {
    case none, basic, bearer
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .basic: return "Basic auth"
        case .bearer: return "Bearer token"
        }
    }
}

/// Connection configuration for an opencode server. The secret (basic-auth
/// password or bearer token) is **not** stored here — it lives in the Keychain,
/// keyed by `id`. Everything in this struct is safe to persist in `UserDefaults`.
struct ServerConfig: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var baseURLString: String
    var authKind: AuthKind = .none
    var username: String = ""
    var extraHeaders: [String: String] = [:]

    /// When set, Korbo never restores a remembered project `directory` for this
    /// server — it always scopes to whatever project the server is currently
    /// serving. Set for BYO tunnels (`korbo up`), whose working directory is
    /// chosen server-side at launch and can change between runs, so it can't be
    /// known — or meaningfully remembered — by the app ahead of time. A stale
    /// remembered directory would scope `GET /session` to an empty list and
    /// strand the user on "No sessions yet" after a relaunch. Optional so configs
    /// persisted by older builds (which lack the key) still decode.
    var usesServerDefaultProject: Bool? = nil

    var baseURL: URL? { URL(string: normalizedURLString) }

    /// Adds a scheme if the user omitted one (defaults to https for remote hosts,
    /// http for loopback) and trims a trailing slash.
    var normalizedURLString: String {
        var s = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return s }
        if !s.contains("://") {
            let isLocal = s.hasPrefix("127.0.0.1") || s.hasPrefix("localhost") || s.hasPrefix("0.0.0.0")
            s = (isLocal ? "http://" : "https://") + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Build the auth + custom headers for a request, reading the secret from the
    /// Keychain on demand.
    func authHeaders() -> [String: String] {
        var headers = extraHeaders
        let secret = Keychain.get(id)
        switch authKind {
        case .none:
            break
        case .basic:
            let raw = "\(username):\(secret ?? "")"
            if let data = raw.data(using: .utf8) {
                headers["Authorization"] = "Basic \(data.base64EncodedString())"
            }
        case .bearer:
            if let secret, !secret.isEmpty {
                headers["Authorization"] = "Bearer \(secret)"
            }
        }
        return headers
    }

    static let localDefault = ServerConfig(
        name: "Local",
        baseURLString: "http://127.0.0.1:4096",
        authKind: .none
    )

    static let korboRemote = ServerConfig(
        name: "korbo.app",
        baseURLString: "https://korbo.app:4096",
        authKind: .basic
    )
}

/// Persists the user's saved servers and which one is selected. Secrets are
/// written through to the Keychain when servers are saved.
@MainActor
final class ServerStore: ObservableObject {
    @Published private(set) var servers: [ServerConfig]
    @Published var selectedServerID: UUID?

    private let serversKey = "korbo.servers.v1"
    private let selectedKey = "korbo.selectedServer.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: serversKey),
           let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data),
           !decoded.isEmpty {
            servers = decoded
        } else {
            // Seed with the local opencode server first (the standard `opencode
            // serve` setup, works out of the box) followed by the korbo.app remote
            // the user is bringing up. Local is selected by default below.
            servers = [ServerConfig.localDefault, ServerConfig.korboRemote]
        }
        if let s = defaults.string(forKey: selectedKey), let uuid = UUID(uuidString: s) {
            selectedServerID = uuid
        } else {
            selectedServerID = servers.first?.id
        }
    }

    var selectedServer: ServerConfig? {
        guard let id = selectedServerID else { return servers.first }
        return servers.first { $0.id == id } ?? servers.first
    }

    /// Insert or update a server, optionally storing a fresh secret in Keychain.
    /// Pass `secret == nil` to leave any existing Keychain secret untouched.
    func save(_ config: ServerConfig, secret: String?) {
        if let secret { Keychain.set(secret, for: config.id) }
        if let idx = servers.firstIndex(where: { $0.id == config.id }) {
            servers[idx] = config
        } else {
            servers.append(config)
        }
        selectedServerID = config.id
        persist()
    }

    func remove(_ config: ServerConfig) {
        Keychain.delete(config.id)
        servers.removeAll { $0.id == config.id }
        if selectedServerID == config.id { selectedServerID = servers.first?.id }
        persist()
    }

    /// Update a saved server's display label in place — without changing the
    /// current selection or its Keychain secret. Used when a cloud/tunnel session
    /// is renamed so its persisted server config (shown in the connection footer
    /// and failure screen) stays in sync with the new name.
    func rename(id: UUID, to name: String) {
        guard let idx = servers.firstIndex(where: { $0.id == id }),
              servers[idx].name != name else { return }
        servers[idx].name = name
        persist()
    }

    func select(_ id: UUID) {
        selectedServerID = id
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(servers) {
            defaults.set(data, forKey: serversKey)
        }
        defaults.set(selectedServerID?.uuidString, forKey: selectedKey)
    }
}
