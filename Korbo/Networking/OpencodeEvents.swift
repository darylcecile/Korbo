import Foundation

/// opencode emits a single SSE stream at `GET /event`. Each event has a `type`
/// discriminator and a `properties` payload. This enumerates the streaming
/// types most relevant to rendering a live conversation. The full taxonomy
/// (77 types) is catalogued in docs/OPENCODE_API.md.
enum OCEventType: String, Codable {
    // session lifecycle
    case sessionCreated = "session.created"
    case sessionUpdated = "session.updated"
    case sessionDeleted = "session.deleted"
    case sessionIdle = "session.idle"
    case sessionError = "session.error"
    case sessionStatus = "session.status"

    // message + parts
    case messageUpdated = "message.updated"
    case messageRemoved = "message.removed"
    case messagePartUpdated = "message.part.updated"
    case messagePartRemoved = "message.part.removed"
    case messagePartDelta = "message.part.delta"

    // streaming deltas (the "next" pipeline)
    case textDelta = "session.next.text.delta"
    case reasoningDelta = "session.next.reasoning.delta"
    case toolCalled = "session.next.tool.called"
    case toolProgress = "session.next.tool.progress"
    case toolSuccess = "session.next.tool.success"
    case toolFailed = "session.next.tool.failed"

    // interaction
    case permissionAsked = "permission.asked"
    case permissionReplied = "permission.replied"
    case questionAsked = "question.asked"
    case todoUpdated = "todo.updated"

    // workspace / vcs
    case fileEdited = "file.edited"
    case fileWatcherUpdated = "file.watcher.updated"
    case vcsBranchUpdated = "vcs.branch.updated"
    case sessionDiff = "session.diff"

    case serverConnected = "server.connected"
}
