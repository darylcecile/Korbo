import Foundation

/// Core opencode data models. Field names and shapes mirror the OpenAPI schema in
/// opencode `packages/sdk/openapi.json` (verified against the live spec). Optional
/// fields are modelled defensively so partial / future payloads still decode.

// MARK: - Session

struct OCSession: Codable, Identifiable, Hashable {
    let id: String
    var slug: String?
    var title: String?
    var projectID: String?
    var workspaceID: String?
    var directory: String?
    var path: String?
    var parentID: String?
    var agent: String?
    var version: String?
    var cost: Double?
    var summary: Summary?
    var tokens: Tokens?
    var model: OCModelRef?
    var share: Share?
    var time: Time?
    var revert: Revert?

    struct Summary: Codable, Hashable {
        var additions: Double?
        var deletions: Double?
        var files: Double?
    }
    struct Tokens: Codable, Hashable {
        var input: Double?
        var output: Double?
        var reasoning: Double?
    }
    struct Share: Codable, Hashable {
        var url: String?
    }
    struct Time: Codable, Hashable {
        var created: Double?
        var updated: Double?
        var archived: Double?
    }

    /// Present when the session has been reverted to an earlier message.
    /// `messageID` is the first reverted (hidden) message; everything from it
    /// onward is undone until `unrevert`.
    struct Revert: Codable, Hashable {
        var messageID: String?
        var partID: String?
        var snapshot: String?
        var diff: String?
    }

    /// Display name for the session's project (last path component of directory).
    var projectName: String? {
        guard let directory, !directory.isEmpty else { return nil }
        return (directory as NSString).lastPathComponent
    }

    var additions: Int { Int(summary?.additions ?? 0) }
    var deletions: Int { Int(summary?.deletions ?? 0) }

    /// Most recent activity timestamp (updated, falling back to created).
    var lastActivity: Date? {
        let ms = time?.updated ?? time?.created
        guard let ms else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    var isArchived: Bool { (time?.archived ?? 0) > 0 }

    /// Whether this session has a published public share link.
    var isShared: Bool { !(share?.url ?? "").isEmpty }
    var shareURL: String? { share?.url }
}

struct OCModelRef: Codable, Hashable {
    var providerID: String
    var modelID: String
    var variant: String?
}

// MARK: - Messages & parts

enum OCMessageRole: String, Codable { case user, assistant }

/// A message together with its ordered parts, as returned by
/// `GET /session/{id}/message` (`[{ info, parts }]`).
struct OCMessageItem: Codable, Identifiable, Hashable {
    var info: OCMessage
    var parts: [OCPart]
    var id: String { info.id }
}

/// Union of UserMessage / AssistantMessage decoded leniently into one struct.
struct OCMessage: Codable, Identifiable, Hashable {
    let id: String
    var sessionID: String
    var role: OCMessageRole
    var time: Time?
    var agent: String?
    var model: OCModelRef?          // user message
    var providerID: String?         // assistant message
    var modelID: String?            // assistant message
    var mode: String?               // assistant message
    var cost: Double?
    var error: OCMessageError?
    var tokens: Usage?

    /// Token accounting carried on an assistant message. `total` already includes
    /// input + output + reasoning + cache, i.e. the context the model processed
    /// for that turn (the basis for the context-window usage bar).
    struct Usage: Codable, Hashable {
        var total: Double?
        var input: Double?
        var output: Double?
        var reasoning: Double?
        var cache: Cache?

        struct Cache: Codable, Hashable {
            var read: Double?
            var write: Double?
        }

        /// Cached tokens (read + write) surfaced as one bucket for the bar.
        var cacheTotal: Double { (cache?.read ?? 0) + (cache?.write ?? 0) }
        /// Best-effort total even if the server omits the precomputed field.
        var resolvedTotal: Double {
            total ?? ((input ?? 0) + (output ?? 0) + (reasoning ?? 0) + cacheTotal)
        }
    }

    struct Time: Codable, Hashable {
        var created: Double?
        var completed: Double?
    }

    var createdAt: Date? {
        guard let ms = time?.created else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
    var completedAt: Date? {
        guard let ms = time?.completed else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
    /// Elapsed wall time for an assistant turn, if completed.
    var duration: TimeInterval? {
        guard let c = createdAt, let e = completedAt else { return nil }
        return e.timeIntervalSince(c)
    }
    /// Best-effort model label for display.
    var modelLabel: String? {
        if let m = model { return m.modelID }
        if let modelID { return modelID }
        return nil
    }
}

/// Assistant error payload (decoded loosely — opencode unions several error types).
struct OCMessageError: Codable, Hashable {
    var name: String?
    var message: String?

    private enum CodingKeys: String, CodingKey { case name, data, message }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decode(String.self, forKey: .name)
        if let direct = try? c.decode(String.self, forKey: .message) {
            message = direct
        } else if let data = try? c.decode(JSONValue.self, forKey: .data) {
            message = data["message"]?.stringValue
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(message, forKey: .message)
    }
}

/// Message part union. opencode parts: text, reasoning, file, tool, step-start,
/// step-finish, snapshot, patch, agent, subtask, retry, compaction.
enum OCPartType: String, Codable {
    case text, reasoning, file, tool
    case stepStart = "step-start"
    case stepFinish = "step-finish"
    case snapshot, patch, agent, subtask, retry, compaction
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OCPartType(rawValue: raw) ?? .unknown
    }
}

/// A single message part decoded leniently across the part union. Only the fields
/// Korbo renders today are surfaced; the rest remain in `state`/raw payloads.
struct OCPart: Codable, Identifiable, Hashable {
    let id: String
    var sessionID: String? = nil
    var messageID: String? = nil
    var type: OCPartType
    var text: String? = nil           // text / reasoning
    var synthetic: Bool? = nil
    var callID: String? = nil         // tool
    var tool: String? = nil           // tool name
    var state: OCToolState? = nil     // tool
    var filename: String? = nil       // file
    var mime: String? = nil           // file
    var url: String? = nil            // file

    var isVisibleText: Bool {
        type == .text && (synthetic != true) && !(text ?? "").isEmpty
    }
}

/// Tool execution lifecycle state (ToolStatePending/Running/Completed/Error).
struct OCToolState: Codable, Hashable {
    var status: OCToolStatus
    var title: String?
    var output: String?
    var error: String?
    var input: JSONValue?
    /// Tool-specific result detail (e.g. edit `diff`, bash `exit`/`output`,
    /// grep `matches`, todowrite `todos`, task `sessionId`/`model`).
    var metadata: JSONValue?
    /// Execution timing (`start`/`end` epoch ms) used to show a duration badge.
    var time: OCToolTime?
}

/// Tool execution timing in epoch milliseconds.
struct OCToolTime: Codable, Hashable {
    var start: Double?
    var end: Double?
}

enum OCToolStatus: String, Codable {
    case pending, running, completed, error, unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OCToolStatus(rawValue: raw) ?? .unknown
    }
}

// MARK: - Providers / models / agents / commands

struct OCProvidersResponse: Codable {
    var all: [OCProvider]
    var connected: [String]
    /// `providerID → default modelID`, as recommended by the opencode server.
    var defaultModels: [String: String]?

    enum CodingKeys: String, CodingKey {
        case all, connected
        case defaultModels = "default"
    }
}

struct OCProvider: Codable, Identifiable, Hashable {
    let id: String
    var name: String?
    var models: [String: OCModel]?
}

struct OCModel: Codable, Identifiable, Hashable {
    let id: String
    var name: String?
    var providerID: String?
    var limit: Limit?
    var capabilities: Capabilities?
    var variants: [String: JSONValue]?

    /// Model context/output token limits (from models.dev via `/provider`).
    struct Limit: Codable, Hashable {
        var context: Double?
        var output: Double?
    }

    /// Model capability flags (only `reasoning` is used; others decode silently).
    struct Capabilities: Codable, Hashable {
        var reasoning: Bool?
    }

    /// Whether this model supports reasoning variants.
    var supportsReasoning: Bool {
        (capabilities?.reasoning ?? false) && !variantNames.isEmpty
    }

    /// Sorted variant keys in canonical order: none < low < medium < high < xhigh.
    var variantNames: [String] {
        guard let variants else { return [] }
        return Array(variants.keys).sorted(by: Self.variantOrder)
    }

    /// Comparator for canonical variant ordering.
    static func variantOrder(_ a: String, _ b: String) -> Bool {
        let order = ["none", "low", "medium", "high", "xhigh"]
        let ai = order.firstIndex(of: a)
        let bi = order.firstIndex(of: b)
        switch (ai, bi) {
        case let (.some(ia), .some(ib)): return ia < ib
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }
}

struct OCAgent: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    var description: String?
    var mode: String?
    var hidden: Bool?
}

struct OCCommand: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    var description: String?
    var agent: String?
}

/// A tool permission request raised mid-run (e.g. a bash/edit tool asking for
/// approval). Decoded leniently; opencode carries extra metadata Korbo ignores.
struct OCPermission: Codable, Identifiable, Hashable {
    let id: String
    var sessionID: String
    var messageID: String?
    var callID: String?
    var type: String?
    var title: String?
    var pattern: String?
}

// MARK: - VCS / files

/// Git/VCS file change status as reported by `/file/status` and `/vcs/status`.
enum OCFileStatus: String, Codable { case added, deleted, modified, unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OCFileStatus(rawValue: raw) ?? .unknown
    }
}

struct OCFileChange: Codable, Identifiable, Hashable {
    var id: String { path }
    let path: String
    var added: Int?
    var removed: Int?
    var status: OCFileStatus?
}

/// `GET /vcs` — current branch and the repository's default branch.
struct OCVcsInfo: Codable, Hashable {
    var branch: String?
    var defaultBranch: String?

    enum CodingKeys: String, CodingKey {
        case branch
        case defaultBranch = "default_branch"
    }
}

/// A single changed file from `GET /vcs/diff` — carries the unified-diff
/// `patch` plus line counts and status. Used by the Git panel's diff viewer.
struct OCVcsFileDiff: Codable, Identifiable, Hashable {
    var id: String { file }
    let file: String
    var patch: String?
    var additions: Int
    var deletions: Int
    var status: OCFileStatus?
}

/// A directory entry from `GET /file?path=` — one level of the workspace tree.
struct OCFileNode: Codable, Identifiable, Hashable {
    let name: String
    let path: String
    let absolute: String
    let type: String
    let ignored: Bool

    var id: String { path }
    var isDirectory: Bool { type == "directory" }
}

/// A file's contents from `GET /file/content?path=` (read-only).
struct OCFileContent: Codable, Hashable {
    let type: String
    let content: String?
    let diff: String?

    var isBinary: Bool { type == "binary" }
}

// MARK: - Terminal (PTY)

/// A pseudo-terminal session from `GET/POST /pty`.
struct OCPty: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let command: String
    let args: [String]
    let cwd: String
    let status: String
    let pid: Int

    var isRunning: Bool { status == "running" }
}

/// An available login shell from `GET /pty/shells`.
struct OCShell: Codable, Identifiable, Hashable {
    let path: String
    let name: String
    let acceptable: Bool

    var id: String { path }
}
