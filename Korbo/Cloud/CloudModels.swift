import Foundation

// MARK: - Date parsing helper

/// Parses ISO8601 timestamps, tolerating both fractional and plain seconds.
/// Returns `nil` on failure so callers can store an optional `Date` without
/// failing the whole decode. Formatters are built fresh to avoid sharing a
/// non-`Sendable` instance across decoding closures.
private func parseISO8601(_ string: String) -> Date? {
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    if let date = plain.date(from: string) { return date }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: string)
}

private extension KeyedDecodingContainer {
    /// Decodes an `Int` tolerating a JSON `Double` (e.g. `5.0`).
    func decodeLenientInt(forKey key: Key) throws -> Int {
        if let i = try? decode(Int.self, forKey: key) { return i }
        let d = try decode(Double.self, forKey: key)
        return Int(d)
    }
}

// MARK: - User & balance

/// Authenticated Korbo account (`GET /api/me`).
struct CloudUser: Codable, Hashable, Identifiable {
    let id: String
    let githubLogin: String?
    let email: String?
    let isAdmin: Bool
}

/// Account credit balance (`GET /api/me`). Credits are whole numbers; the JSON
/// may serialise them as `Double`, so decoding tolerates both.
struct CloudBalance: Codable, Hashable {
    let balance: Int
    let reserved: Int
    let available: Int

    init(balance: Int, reserved: Int, available: Int) {
        self.balance = balance
        self.reserved = reserved
        self.available = available
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        balance = try c.decodeLenientInt(forKey: .balance)
        reserved = try c.decodeLenientInt(forKey: .reserved)
        available = try c.decodeLenientInt(forKey: .available)
    }
}

// MARK: - Instances

/// Lifecycle state of a provisioned instance. Unrecognised strings decode to
/// `.unknown` rather than failing.
enum CloudInstanceState: String, Codable, Hashable, CaseIterable {
    case provisioning
    case starting
    case ready
    case sleeping
    case resuming
    case suspended
    case error
    case terminated
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CloudInstanceState(rawValue: raw) ?? .unknown
    }

    /// The instance's opencode proxy is reachable.
    var isReady: Bool { self == .ready }

    /// The instance is mid-lifecycle and should be polled until it settles.
    var isTransitional: Bool {
        self == .provisioning || self == .starting || self == .resuming
    }

    /// The instance has reached a terminal state and will not become ready
    /// without further action. NOTE: `.suspended` is intentionally NOT terminal —
    /// an out-of-credits instance retains its workspace + session snapshot and
    /// becomes ready again once the user tops up and reconnects (the proxy
    /// triggers a server-side resume).
    var isTerminal: Bool {
        self == .error || self == .terminated
    }

    /// Out of credits but recoverable: workspace + conversation are retained for
    /// a retention window. Top up + Connect resumes it.
    var isSuspended: Bool { self == .suspended }

    /// Human-friendly label for the state.
    var displayLabel: String {
        switch self {
        case .provisioning: return "Provisioning"
        case .starting:     return "Starting"
        case .ready:        return "Ready"
        case .sleeping:     return "Sleeping"
        case .resuming:     return "Resuming"
        case .suspended:    return "Suspended"
        case .error:        return "Error"
        case .terminated:   return "Terminated"
        case .unknown:      return "Unknown"
        }
    }
}

/// A provisioned cloud instance (`InstanceView`). Timestamps decode from ISO8601
/// strings and fall back to `nil` on malformed values.
struct CloudInstance: Codable, Hashable, Identifiable {
    let id: String
    let machineType: String
    let state: CloudInstanceState
    let repo: String?
    let reason: String?
    let createdAt: Date?
    let expiresAt: Date?
    /// Suspended-retention deadline: after this the retained workspace + snapshot
    /// are reclaimed. Present only while suspended-recoverable; `nil` otherwise.
    let purgeAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, machineType, state, repo, reason, createdAt, expiresAt, purgeAt
    }

    init(
        id: String,
        machineType: String,
        state: CloudInstanceState,
        repo: String?,
        reason: String?,
        createdAt: Date?,
        expiresAt: Date?,
        purgeAt: Date? = nil
    ) {
        self.id = id
        self.machineType = machineType
        self.state = state
        self.repo = repo
        self.reason = reason
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.purgeAt = purgeAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        machineType = try c.decode(String.self, forKey: .machineType)
        state = try c.decode(CloudInstanceState.self, forKey: .state)
        repo = try c.decodeIfPresent(String.self, forKey: .repo)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        createdAt = (try c.decodeIfPresent(String.self, forKey: .createdAt)).flatMap(parseISO8601)
        expiresAt = (try c.decodeIfPresent(String.self, forKey: .expiresAt)).flatMap(parseISO8601)
        purgeAt = (try c.decodeIfPresent(String.self, forKey: .purgeAt)).flatMap(parseISO8601)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(machineType, forKey: .machineType)
        try c.encode(state.rawValue, forKey: .state)
        try c.encodeIfPresent(repo, forKey: .repo)
        try c.encodeIfPresent(reason, forKey: .reason)
        let formatter = ISO8601DateFormatter()
        try c.encodeIfPresent(createdAt.map(formatter.string(from:)), forKey: .createdAt)
        try c.encodeIfPresent(expiresAt.map(formatter.string(from:)), forKey: .expiresAt)
        try c.encodeIfPresent(purgeAt.map(formatter.string(from:)), forKey: .purgeAt)
    }
}

extension CloudInstance {
    /// Short, human-friendly label for the instance: the repo (`owner/name`) when
    /// known, otherwise a truncated instance id. Used by the instance switcher,
    /// command palette, and the saved `ServerConfig` name so users never have to
    /// read a raw instance id.
    var displayName: String {
        let trimmed = repo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Instance \(id.suffix(6))" : trimmed
    }
}

/// How an instance's `/workspace` was materialized on its most recent resume.
/// Only meaningful when the owning state is `.ready` (the backend clears this at
/// every resume start and re-sets it per materialization, so it is never stale
/// for the current ready window). `null` on a fresh provision.
enum WorkspaceRestore: String, Codable, Hashable {
    /// Restored verbatim from the R2 whole-workspace snapshot (full fidelity).
    case full
    /// No usable snapshot — the base repo was re-cloned from origin, so any
    /// local-only edits made before the last sleep were NOT carried over.
    case reclone
    /// Nothing to restore and no repo to clone — started from an empty tree.
    case empty
}

/// Detailed runtime state for a single instance (`GET /api/instances/:id/state`).
struct CloudInstanceStateDetail: Codable, Hashable, Identifiable {
    let id: String
    let state: CloudInstanceState
    let machineType: String
    let reason: String?
    let expiresAt: Date?
    let purgeAt: Date?
    let creditsPerMinute: Double
    let balanceCredits: Double
    /// How `/workspace` was materialized on the latest resume (see
    /// `WorkspaceRestore`). Only interpret when `state == .ready`.
    let workspaceRestore: WorkspaceRestore?
    /// True when the restored tree is a faithful `full` restore of a snapshot
    /// that is older than suspend-time work (a prior suspend couldn't snapshot),
    /// so the contents may be slightly behind the user's last edits.
    let workspaceRestoreStale: Bool

    enum CodingKeys: String, CodingKey {
        case id, state, machineType, reason, expiresAt, purgeAt, creditsPerMinute, balanceCredits
        case workspaceRestore, workspaceRestoreStale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        state = try c.decode(CloudInstanceState.self, forKey: .state)
        machineType = try c.decode(String.self, forKey: .machineType)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        expiresAt = (try c.decodeIfPresent(String.self, forKey: .expiresAt)).flatMap(parseISO8601)
        purgeAt = (try c.decodeIfPresent(String.self, forKey: .purgeAt)).flatMap(parseISO8601)
        creditsPerMinute = try c.decode(Double.self, forKey: .creditsPerMinute)
        balanceCredits = try c.decode(Double.self, forKey: .balanceCredits)
        // Tolerate an unknown/absent restore enum (forward-compat with new
        // backend values) by mapping anything unrecognized to nil.
        workspaceRestore = (try c.decodeIfPresent(String.self, forKey: .workspaceRestore))
            .flatMap(WorkspaceRestore.init(rawValue:))
        workspaceRestoreStale = (try c.decodeIfPresent(Bool.self, forKey: .workspaceRestoreStale)) ?? false
    }
}

// MARK: - Self-hosted (BYO) sessions

/// Online/offline status of a bring-your-own-machine session. Unrecognised
/// strings decode to `.offline` (the safe default for connection gating) while
/// preserving the raw value via `CloudSession.rawStatus` for diagnostics.
enum CloudSessionStatus: String, Codable, Hashable, CaseIterable {
    case online
    case offline

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CloudSessionStatus(rawValue: raw) ?? .offline
    }

    /// The session's local opencode is reachable through the proxy.
    var isOnline: Bool { self == .online }

    var displayLabel: String {
        switch self {
        case .online:  return "Online"
        case .offline: return "Offline"
        }
    }
}

/// A self-hosted ("bring your own machine") opencode session registered by the
/// `korbo` CLI (`GET /api/sessions`). Reached through the same per-host proxy as
/// managed instances, but free and with a simple online/offline status instead
/// of a provisioning lifecycle. Timestamps decode from ISO8601 and fall back to
/// `nil` on malformed values.
struct CloudSession: Codable, Hashable, Identifiable {
    let id: String
    let name: String?
    let repo: String?
    let status: CloudSessionStatus
    /// Full proxy host (e.g. `byo-abc123.cloud.korbo.app`) used verbatim to build
    /// the opencode base URL. Kept domain-agnostic so the app isn't coupled to a
    /// hardcoded cloud host.
    let proxyHost: String
    let createdAt: Date?
    let lastHeartbeat: Date?
    /// The raw `status` string as received, retained for diagnostics so a future
    /// backend value (e.g. `degraded`) isn't silently indistinguishable from a
    /// genuine `offline`.
    let rawStatus: String

    enum CodingKeys: String, CodingKey {
        case id, name, repo, status, proxyHost, createdAt, lastHeartbeat
    }

    init(
        id: String,
        name: String?,
        repo: String?,
        status: CloudSessionStatus,
        proxyHost: String,
        createdAt: Date?,
        lastHeartbeat: Date?,
        rawStatus: String? = nil
    ) {
        self.id = id
        self.name = name
        self.repo = repo
        self.status = status
        self.proxyHost = proxyHost
        self.createdAt = createdAt
        self.lastHeartbeat = lastHeartbeat
        self.rawStatus = rawStatus ?? status.rawValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        repo = try c.decodeIfPresent(String.self, forKey: .repo)
        let raw = try c.decodeIfPresent(String.self, forKey: .status) ?? "offline"
        rawStatus = raw
        status = CloudSessionStatus(rawValue: raw) ?? .offline
        proxyHost = try c.decode(String.self, forKey: .proxyHost)
        createdAt = (try c.decodeIfPresent(String.self, forKey: .createdAt)).flatMap(parseISO8601)
        lastHeartbeat = (try c.decodeIfPresent(String.self, forKey: .lastHeartbeat)).flatMap(parseISO8601)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(repo, forKey: .repo)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(proxyHost, forKey: .proxyHost)
        let formatter = ISO8601DateFormatter()
        try c.encodeIfPresent(createdAt.map(formatter.string(from:)), forKey: .createdAt)
        try c.encodeIfPresent(lastHeartbeat.map(formatter.string(from:)), forKey: .lastHeartbeat)
    }
}

extension CloudSession {
    /// Short, human-friendly label: the user-given name, else the repo, else a
    /// truncated id. Mirrors `CloudInstance.displayName` so shared UI can treat
    /// both uniformly.
    var displayName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty { return trimmedName }
        let trimmedRepo = repo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedRepo.isEmpty { return trimmedRepo }
        return "Session \(id.suffix(6))"
    }
}

// MARK: - GitHub linkage

/// A GitHub App installation available to the account
/// (`GET /api/github/installations`).
struct CloudInstallation: Codable, Hashable, Identifiable {
    let id: Int
    let account: String
}

/// A repository the account can launch an instance against
/// (`GET /api/github/repos`). Decoded defensively because the backend payload
/// shape is not fully pinned down: accepts a top-level `full_name`, or an
/// `{ owner, name }` pair (owner may itself be a string or `{ login }`).
struct CloudRepo: Codable, Hashable, Identifiable {
    let fullName: String

    var id: String { fullName }

    init(fullName: String) {
        self.fullName = fullName
    }

    private enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case name
        case owner
    }

    private enum OwnerKeys: String, CodingKey {
        case login
        case name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let full = try c.decodeIfPresent(String.self, forKey: .fullName), !full.isEmpty {
            fullName = full
            return
        }
        let name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        var ownerString: String?
        if let owner = try? c.decodeIfPresent(String.self, forKey: .owner) {
            ownerString = owner
        } else if let ownerContainer = try? c.nestedContainer(keyedBy: OwnerKeys.self, forKey: .owner) {
            ownerString = (try? ownerContainer.decodeIfPresent(String.self, forKey: .login))
                ?? (try? ownerContainer.decodeIfPresent(String.self, forKey: .name))
                ?? nil
        }
        if let owner = ownerString, !owner.isEmpty, !name.isEmpty {
            fullName = "\(owner)/\(name)"
        } else {
            fullName = name
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fullName, forKey: .fullName)
    }
}

// MARK: - Machine types

/// A selectable instance machine type with a friendly label. The catalogue is
/// fixed client-side; see `CloudMachineType.all`.
struct CloudMachineType: Hashable, Identifiable {
    let id: String
    let label: String
    let isDefault: Bool

    init(id: String, label: String, isDefault: Bool = false) {
        self.id = id
        self.label = label
        self.isDefault = isDefault
    }

    /// The six supported machine types with hardcoded spec labels.
    static let all: [CloudMachineType] = [
        CloudMachineType(id: "lite", label: "lite · 1/16 vCPU / 0.25 GiB"),
        CloudMachineType(id: "basic", label: "basic · 1/4 vCPU / 1 GiB"),
        CloudMachineType(id: "standard-1", label: "standard-1 · 1/2 vCPU / 4 GiB", isDefault: true),
        CloudMachineType(id: "standard-2", label: "standard-2 · 1 vCPU / 6 GiB"),
        CloudMachineType(id: "standard-3", label: "standard-3 · 2 vCPU / 8 GiB"),
        CloudMachineType(id: "standard-4", label: "standard-4 · 4 vCPU / 12 GiB"),
    ]

    /// The default machine type (`standard-1`).
    static let `default`: CloudMachineType = all.first { $0.isDefault } ?? all[2]
}

// MARK: - Response envelopes

struct CloudMeResponse: Decodable {
    let user: CloudUser
    let balance: CloudBalance
}

struct CloudInstancesResponse: Decodable {
    let instances: [CloudInstance]
}

struct CloudInstanceResponse: Decodable {
    let instance: CloudInstance
}

struct CloudSessionsResponse: Decodable {
    let sessions: [CloudSession]
}

struct CloudSessionResponse: Decodable {
    let session: CloudSession
}

struct CloudInstallationsResponse: Decodable {
    let installations: [CloudInstallation]
}

struct CloudReposResponse: Decodable {
    let repositories: [CloudRepo]
}

struct CloudTopupResponse: Decodable {
    let url: String
}

struct CloudOKResponse: Decodable {
    let ok: Bool
}
