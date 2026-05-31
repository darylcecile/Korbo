import Foundation

/// opencode emits a single SSE stream at `GET /event`. Each frame is
/// `data: { "type": "…", "properties": { … } }`. There are 77 event types
/// (catalogued in docs/OPENCODE_API.md); Korbo decodes the envelope and handles
/// the subset it needs, ignoring the rest gracefully.
struct OCEvent: Decodable {
    let type: String
    let properties: JSONValue

    private enum CodingKeys: String, CodingKey { case type, properties }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        properties = (try? c.decode(JSONValue.self, forKey: .properties)) ?? .null
    }
}

/// The streaming event types Korbo acts on. Anything else is ignored.
enum OCEventType: String {
    // session lifecycle
    case sessionCreated = "session.created"
    case sessionUpdated = "session.updated"
    case sessionDeleted = "session.deleted"
    case sessionIdle = "session.idle"
    case sessionError = "session.error"

    // message + parts (carry full objects in `properties`)
    case messageUpdated = "message.updated"
    case messageRemoved = "message.removed"
    case messagePartUpdated = "message.part.updated"
    case messagePartRemoved = "message.part.removed"

    // interaction
    case permissionAsked = "permission.asked"
    case questionAsked = "question.asked"

    // workspace / vcs
    case fileEdited = "file.edited"
    case vcsBranchUpdated = "vcs.branch.updated"

    // connectivity
    case serverConnected = "server.connected"
}
