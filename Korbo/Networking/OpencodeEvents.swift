import Foundation

/// opencode broadcasts a single SSE stream of domain events. On this build the
/// useful stream is `GET /global/event`, where each frame wraps the real event
/// in a `payload` envelope (`data: { "payload": { "type": …, "properties": … } }`)
/// and also re-emits a `sync`-wrapped duplicate that Korbo ignores. The plain
/// `GET /event` endpoint only ever yields `server.connected` on this version, so
/// Korbo subscribes to `/global/event`. There are 77 event types (catalogued in
/// docs/OPENCODE_API.md); Korbo decodes the envelope and handles the subset it
/// needs, ignoring the rest gracefully.
struct OCEvent: Decodable {
    let type: String
    let properties: JSONValue

    private enum CodingKeys: String, CodingKey { case type, properties, payload }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `/global/event` nests the real event under `payload`; unwrap it.
        if let payload = try? c.decode(OCEvent.self, forKey: .payload) {
            type = payload.type
            properties = payload.properties
            return
        }
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
    case sessionStatus = "session.status"
    case sessionIdle = "session.idle"
    case sessionError = "session.error"

    // message + parts (carry full objects in `properties`)
    case messageUpdated = "message.updated"
    case messageRemoved = "message.removed"
    case messagePartUpdated = "message.part.updated"
    case messagePartDelta = "message.part.delta"
    case messagePartRemoved = "message.part.removed"

    // interaction
    case permissionAsked = "permission.asked"
    case questionAsked = "question.asked"

    // workspace / vcs
    case fileEdited = "file.edited"
    case vcsBranchUpdated = "vcs.branch.updated"
    case sessionDiff = "session.diff"

    // connectivity
    case serverConnected = "server.connected"
}
