import Foundation
import Combine

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var isConnected: Bool { if case .connected = self { return true }; return false }
    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .failed: return "Connection failed"
        }
    }
}

/// Central data + connection store. Owns the active `OpencodeClient`, performs the
/// health probe, maintains the long-lived SSE subscription (with reconnect), and
/// keeps the session list + selected conversation in sync from both REST and
/// streamed events.
@MainActor
final class KorboStore: ObservableObject {
    let servers: ServerStore

    @Published private(set) var status: ConnectionStatus = .disconnected
    @Published private(set) var sessions: [OCSession] = []
    @Published var selectedSessionID: String?
    @Published private(set) var messages: [OCMessageItem] = []
    @Published private(set) var providers: OCProvidersResponse?
    @Published private(set) var agents: [OCAgent] = []
    @Published private(set) var commands: [OCCommand] = []
    @Published private(set) var isLoadingMessages = false
    @Published private(set) var lastError: String?
    /// Sessions with an in-progress assistant run (drives the typing indicator
    /// and the composer's stop button). Kept in sync from `session.status` /
    /// `session.idle` events.
    @Published private(set) var activeSessionIDs: Set<String> = []
    /// Tool permission requests awaiting a user decision (inline cards in chat).
    @Published private(set) var pendingPermissions: [OCPermission] = []

    /// Git panel state: branch info + the changed files for the current diff mode.
    @Published private(set) var vcsInfo: OCVcsInfo?
    @Published private(set) var gitFiles: [OCVcsFileDiff] = []
    @Published private(set) var isLoadingGit = false
    /// Which diff the Git panel shows. Setting it reloads via `loadGit()`.
    @Published var gitMode: GitMode = .working

    /// Live text filter applied to the sessions sidebar (matches title/project).
    @Published var sessionQuery: String = ""

    /// The two diff views opencode exposes through `/vcs/diff`.
    enum GitMode: String, CaseIterable, Identifiable {
        case working, branch
        var id: String { rawValue }
        /// `/vcs/diff?mode=` query value.
        var query: String { self == .working ? "git" : "branch" }
        var title: String { self == .working ? "Working" : "Branch" }
    }

    /// Whether the selected session is currently generating a reply.
    var isGenerating: Bool {
        guard let id = selectedSessionID else { return false }
        return activeSessionIDs.contains(id)
    }

    private var client: OpencodeClient?
    private var eventTask: Task<Void, Never>?

    init(servers: ServerStore? = nil) {
        self.servers = servers ?? ServerStore()
    }

    var selectedSession: OCSession? {
        guard let id = selectedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    // MARK: - Connection lifecycle

    /// Probe health for the selected server, then load sessions and start the
    /// event stream. Safe to call repeatedly (e.g. retry).
    func connect() async {
        guard let server = servers.selectedServer, server.baseURL != nil else {
            status = .failed("No server configured")
            return
        }
        await teardown()
        status = .connecting
        lastError = nil
        let client = OpencodeClient(config: server)
        self.client = client

        do {
            let ok = try await client.health()
            guard ok else {
                status = .failed("Server health check failed")
                return
            }
            status = .connected
            await reloadSessions()
            await loadMetadata()
            await loadGit()
            startEventStream()
        } catch {
            let message = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
            status = .failed(message)
            lastError = message
        }
    }

    func disconnect() async {
        await teardown()
        status = .disconnected
    }

    private func teardown() async {
        eventTask?.cancel()
        eventTask = nil
        activeSessionIDs.removeAll()
        pendingPermissions.removeAll()
        vcsInfo = nil
        gitFiles = []
    }

    // MARK: - Loading

    func reloadSessions() async {
        guard let client else { return }
        do {
            let list = try await client.listSessions()
            sessions = sortSessions(list)
            if selectedSessionID == nil {
                selectedSessionID = sessions.first?.id
            }
            if let id = selectedSessionID {
                await loadMessages(sessionID: id)
            }
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadMetadata() async {
        guard let client else { return }
        async let providersResult = try? client.listProviders()
        async let agentsResult = try? client.listAgents()
        async let commandsResult = try? client.listCommands()
        let p = await providersResult
        let a = await agentsResult
        let c = await commandsResult
        providers = p
        agents = a ?? []
        commands = c ?? []
    }

    func selectSession(_ id: String) async {
        selectedSessionID = id
        await loadMessages(sessionID: id)
    }

    // MARK: - Git / VCS

    /// Refresh the Git panel: branch info plus the changed files for the current
    /// `gitMode`. Failures are surfaced via `lastError` but leave prior data intact
    /// (a transient diff error shouldn't blank the panel).
    func loadGit() async {
        guard let client else { return }
        isLoadingGit = true
        defer { isLoadingGit = false }
        let mode = gitMode
        async let infoResult = try? client.vcsInfo()
        async let filesResult = try? client.vcsDiff(mode: mode.query)
        let info = await infoResult
        let files = await filesResult
        if let info { vcsInfo = info }
        // Only replace the file list if the request succeeded and the mode is still
        // current (the user may have toggled while the request was in flight).
        if let files, mode == gitMode {
            gitFiles = files
        }
    }

    /// Switch diff mode and reload.
    func setGitMode(_ mode: GitMode) async {
        guard mode != gitMode else { return }
        gitMode = mode
        gitFiles = []
        await loadGit()
    }

    /// `POST /session` then select the new session.
    func createSession() async {
        guard let client else { return }
        do {
            let session = try await client.createSession()
            upsertSession(session)
            selectedSessionID = session.id
            messages = []
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Session management (rename / archive / delete / grouping)

    /// Root sessions (sub-sessions/forks are hidden from the top list) matching
    /// the current `sessionQuery`, bucketed into recency groups plus Archived.
    var sessionGroups: [SessionGroup] {
        let q = sessionQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = sessions.filter { session in
            guard (session.parentID ?? "").isEmpty else { return false }
            guard !q.isEmpty else { return true }
            return (session.title ?? "").lowercased().contains(q)
                || (session.projectName ?? "").lowercased().contains(q)
        }

        var buckets: [SessionBucket: [OCSession]] = [:]
        for session in visible {
            buckets[bucket(for: session), default: []].append(session)
        }
        return SessionBucket.allCases.compactMap { b in
            guard let items = buckets[b], !items.isEmpty else { return nil }
            return SessionGroup(bucket: b, sessions: items)
        }
    }

    private func bucket(for session: OCSession) -> SessionBucket {
        if session.isArchived { return .archived }
        guard let date = session.lastActivity else { return .older }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return .week
        }
        return .older
    }

    /// `PATCH /session/{id}` rename, then merge the returned session.
    func renameSession(_ id: String, title: String) async {
        guard let client else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let updated = try await client.updateSessionTitle(id, title: trimmed)
            upsertSession(updated)
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Archive or unarchive a session.
    func setSessionArchived(_ id: String, archived: Bool) async {
        guard let client else { return }
        do {
            let updated = try await client.setSessionArchived(id, archived: archived)
            upsertSession(updated)
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Delete a session; if it was selected, fall back to the next available one.
    func deleteSession(_ id: String) async {
        guard let client else { return }
        do {
            try await client.deleteSession(id)
            sessions.removeAll { $0.id == id }
            if selectedSessionID == id {
                selectedSessionID = sessions.first?.id
                if let next = selectedSessionID {
                    await loadMessages(sessionID: next)
                } else {
                    messages = []
                }
            }
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Send a text prompt to the selected session via `prompt_async`. The reply
    /// streams live over `/global/event` (message/part updates + token deltas).
    /// We mark the session active immediately for instant UI feedback and do one
    /// REST reload so the user's message renders with its real ID; from there the
    /// event stream drives everything until `session.idle`.
    func sendPrompt(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client, let sid = selectedSessionID, !trimmed.isEmpty else { return }
        var body: [String: Any] = [
            "parts": [["type": "text", "text": trimmed]]
        ]
        if let model = resolveModel() {
            body["model"] = ["providerID": model.providerID, "modelID": model.modelID]
        }
        activeSessionIDs.insert(sid)
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            try await client.sendPromptAsync(sessionID: sid, body: data)
            await loadMessages(sessionID: sid)
        } catch {
            activeSessionIDs.remove(sid)
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// `POST /session/{id}/abort` — stop the in-progress run for the selected
    /// session and reconcile from REST.
    func abort() async {
        guard let client, let sid = selectedSessionID else { return }
        do {
            try await client.abort(sessionID: sid)
            activeSessionIDs.remove(sid)
            await loadMessages(sessionID: sid)
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Reply to a tool permission request (`once` / `always` / `reject`).
    func replyPermission(_ permission: OCPermission, response: String) async {
        guard let client else { return }
        do {
            try await client.replyPermission(sessionID: permission.sessionID,
                                              permissionID: permission.id,
                                              response: response)
            pendingPermissions.removeAll { $0.id == permission.id }
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Best-effort model selection: the session's last-used model, else the first
    /// connected provider's first model.
    /// Best-effort model selection for a new prompt:
    /// 1. the session's last-used model, if any;
    /// 2. otherwise a connected provider (preferring github-copilot, then other
    ///    common hosts) paired with the opencode-recommended default model.
    /// A full in-app model picker arrives in a later milestone.
    func resolveModel() -> OCModelRef? {
        if let m = selectedSession?.model { return m }
        guard let providers else { return nil }

        let preferred = ["github-copilot", "anthropic", "openai", "opencode"]
        let ordered = preferred.filter { providers.connected.contains($0) }
            + providers.connected.filter { !preferred.contains($0) }

        for pid in ordered {
            guard let provider = providers.all.first(where: { $0.id == pid }) else { continue }
            let models = provider.models ?? [:]
            if let def = providers.defaultModels?[pid], models[def] != nil {
                return OCModelRef(providerID: pid, modelID: def)
            }
            if let modelID = models.keys.sorted().first {
                return OCModelRef(providerID: pid, modelID: modelID)
            }
        }
        if let provider = providers.all.first,
           let modelID = provider.models?.keys.sorted().first {
            return OCModelRef(providerID: provider.id, modelID: modelID)
        }
        return nil
    }

    func loadMessages(sessionID: String) async {
        guard let client else { return }
        isLoadingMessages = true
        defer { isLoadingMessages = false }
        do {
            let items = try await client.listMessages(sessionID: sessionID)
            // Guard against a race where selection changed mid-flight.
            if selectedSessionID == sessionID {
                messages = items
            }
        } catch {
            if selectedSessionID == sessionID { messages = [] }
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Event stream

    private func startEventStream() {
        guard let client else { return }
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            var backoff: UInt64 = 1
            while !Task.isCancelled {
                do {
                    for try await event in client.events() {
                        self?.handle(event)
                        backoff = 1
                    }
                } catch {
                    // stream dropped; fall through to reconnect with backoff
                }
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                backoff = min(backoff * 2, 30)
            }
        }
    }

    private func handle(_ event: OCEvent) {
        guard let type = OCEventType(rawValue: event.type) else { return }
        let props = event.properties
        switch type {
        case .sessionCreated, .sessionUpdated:
            if let session = props["info"]?.decode(OCSession.self) {
                upsertSession(session)
            }
        case .sessionDeleted:
            let id = props["info"]?["id"]?.stringValue ?? props["id"]?.stringValue
            if let id { sessions.removeAll { $0.id == id } }
        case .sessionStatus:
            // `{ sessionID, status: { type: "busy" | "idle" | … } }`
            if let sid = props["sessionID"]?.stringValue {
                let kind = props["status"]?["type"]?.stringValue
                if kind == "idle" { markIdle(sid) } else { activeSessionIDs.insert(sid) }
            }
        case .sessionIdle:
            if let sid = props["sessionID"]?.stringValue { markIdle(sid) }
        case .messageUpdated:
            if let message = props["info"]?.decode(OCMessage.self) {
                upsertMessageInfo(message)
            }
        case .messageRemoved:
            let mid = props["messageID"]?.stringValue ?? props["info"]?["id"]?.stringValue
            if let mid { messages.removeAll { $0.info.id == mid } }
        case .messagePartUpdated:
            if let part = props["part"]?.decode(OCPart.self) {
                upsertPart(part)
            }
        case .messagePartDelta:
            // `{ sessionID, messageID, partID, field, delta }` — append streamed text.
            if let mid = props["messageID"]?.stringValue,
               let pid = props["partID"]?.stringValue,
               let delta = props["delta"]?.stringValue {
                appendDelta(messageID: mid, partID: pid,
                            field: props["field"]?.stringValue ?? "text", delta: delta)
            }
        case .messagePartRemoved:
            let mid = props["messageID"]?.stringValue
            let pid = props["partID"]?.stringValue ?? props["part"]?["id"]?.stringValue
            if let mid, let pid, let idx = messages.firstIndex(where: { $0.info.id == mid }) {
                messages[idx].parts.removeAll { $0.id == pid }
            }
        case .permissionAsked:
            if let permission = props.decode(OCPermission.self) ?? props["info"]?.decode(OCPermission.self) {
                if !pendingPermissions.contains(where: { $0.id == permission.id }) {
                    pendingPermissions.append(permission)
                }
            }
        case .sessionError, .questionAsked, .serverConnected:
            break // handled in later milestones
        case .fileEdited, .vcsBranchUpdated, .sessionDiff:
            // The working tree or branch changed — refresh the Git panel.
            Task { [weak self] in await self?.loadGit() }
        }
    }

    /// Mark a session's run finished and reconcile its messages from REST so the
    /// final authoritative state (completed time, cost, tokens) is correct even if
    /// some streamed frames were missed.
    private func markIdle(_ sessionID: String) {
        activeSessionIDs.remove(sessionID)
        pendingPermissions.removeAll { $0.sessionID == sessionID }
        if sessionID == selectedSessionID {
            Task { [weak self] in await self?.loadMessages(sessionID: sessionID) }
        }
    }

    // MARK: - Merge helpers

    private func upsertSession(_ session: OCSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        sessions = sortSessions(sessions)
    }

    private func upsertMessageInfo(_ message: OCMessage) {
        guard message.sessionID == selectedSessionID else { return }
        if let idx = messages.firstIndex(where: { $0.info.id == message.id }) {
            messages[idx].info = message
        } else {
            messages.append(OCMessageItem(info: message, parts: []))
        }
    }

    private func upsertPart(_ part: OCPart) {
        guard let mid = part.messageID,
              let idx = messages.firstIndex(where: { $0.info.id == mid }) else { return }
        if let pidx = messages[idx].parts.firstIndex(where: { $0.id == part.id }) {
            // Preserve any text already streamed in via deltas if the snapshot is
            // empty (snapshots can arrive after deltas during a live run).
            var incoming = part
            if (incoming.text ?? "").isEmpty, let existing = messages[idx].parts[pidx].text, !existing.isEmpty {
                incoming.text = existing
            }
            messages[idx].parts[pidx] = incoming
        } else {
            messages[idx].parts.append(part)
        }
    }

    /// Append a streamed token delta to a part's text/reasoning field, creating a
    /// stub part if the snapshot hasn't arrived yet.
    private func appendDelta(messageID: String, partID: String, field: String, delta: String) {
        guard let midx = messages.firstIndex(where: { $0.info.id == messageID }) else { return }
        guard field == "text" || field == "reasoning" else { return }
        if let pidx = messages[midx].parts.firstIndex(where: { $0.id == partID }) {
            messages[midx].parts[pidx].text = (messages[midx].parts[pidx].text ?? "") + delta
        } else {
            let part = OCPart(id: partID,
                              sessionID: messages[midx].info.sessionID,
                              messageID: messageID,
                              type: field == "reasoning" ? .reasoning : .text,
                              text: delta)
            messages[midx].parts.append(part)
        }
    }

    private func sortSessions(_ list: [OCSession]) -> [OCSession] {
        list.sorted {
            ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
        }
    }
}

// MARK: - Session grouping

/// Recency buckets for the sessions sidebar, in display order.
enum SessionBucket: String, CaseIterable, Identifiable {
    case today, yesterday, week, older, archived
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today:     return "Today"
        case .yesterday: return "Yesterday"
        case .week:      return "Previous 7 days"
        case .older:     return "Older"
        case .archived:  return "Archived"
        }
    }
}

/// A titled section of sessions for the sidebar.
struct SessionGroup: Identifiable {
    let bucket: SessionBucket
    let sessions: [OCSession]
    var id: String { bucket.id }
    var title: String { bucket.title }
}
