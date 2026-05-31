import Foundation

/// Core opencode data models (subset). Field names mirror the OpenAPI schema in
/// opencode `packages/sdk/openapi.json`. Expand as features are implemented.

struct OCSession: Codable, Identifiable, Hashable {
    let id: String
    var title: String?
    var projectID: String?
    var directory: String?
    var parentID: String?
    var agent: String?
    var cost: Double?
    var version: String?
}

struct OCModelRef: Codable, Hashable {
    var providerID: String
    var modelID: String
}

enum OCMessageRole: String, Codable { case user, assistant }

/// Message part union. opencode parts: text, reasoning, file, tool, step-start,
/// step-finish, snapshot, patch, agent, subtask, retry, compaction.
enum OCPartType: String, Codable {
    case text, reasoning, file, tool
    case stepStart = "step-start"
    case stepFinish = "step-finish"
    case snapshot, patch, agent, subtask, retry, compaction
}

/// Tool execution lifecycle states.
enum OCToolStatus: String, Codable { case pending, running, completed, error }

/// Git/VCS file change status as reported by /file/status and /vcs/status.
enum OCFileStatus: String, Codable { case added, deleted, modified }
