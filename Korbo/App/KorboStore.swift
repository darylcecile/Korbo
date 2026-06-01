import Foundation
import Combine

/// A read-only file open in a viewer tab. Content is loaded lazily and cached
/// so re-selecting a tab is instant.
struct OpenFile: Identifiable, Equatable {
    let path: String
    var content: OCFileContent?
    var isLoading: Bool
    var id: String { path }
}

/// A file/image staged in the composer, ready to send as an opencode `file`
/// part. `dataURL` is a `data:<mime>;base64,<…>` string.
struct ComposerAttachment: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let mime: String
    let dataURL: String
}

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

    /// How the sessions sidebar is grouped and ordered (persisted).
    @Published private(set) var sessionGrouping: SessionGrouping = .recency
    @Published private(set) var sessionSort: SessionSort = .recent

    func setSessionGrouping(_ g: SessionGrouping) {
        sessionGrouping = g
        UserDefaults.standard.set(g.rawValue, forKey: Self.groupingDefaultsKey)
    }
    func setSessionSort(_ s: SessionSort) {
        sessionSort = s
        UserDefaults.standard.set(s.rawValue, forKey: Self.sortDefaultsKey)
    }

    /// File explorer (read-only) state. The tree loads lazily one directory at a
    /// time: `fileChildren[dirPath]` holds that directory's entries once fetched.
    @Published private(set) var fileChildren: [String: [OCFileNode]] = [:]
    @Published var expandedDirs: Set<String> = []
    @Published private(set) var loadingDirs: Set<String> = []
    /// Open file tabs (read-only). The viewer shows `activeFilePath`; the browser
    /// shows when `openFiles` is empty. Each tab caches its own loaded content so
    /// switching tabs is instant after the first load.
    @Published private(set) var openFiles: [OpenFile] = []
    @Published var activeFilePath: String?
    @Published var fileQuery: String = ""
    @Published private(set) var fileSearchResults: [String] = []
    @Published private(set) var isSearchingFiles = false

    /// User-chosen model/agent overrides for new prompts. `nil` means "let the
    /// store auto-resolve" (see `resolveModel`/`resolveAgent`). Persisted globally
    /// across launches via `UserDefaults`.
    @Published private(set) var selectedModelOverride: OCModelRef?
    @Published private(set) var selectedAgentName: String?
    /// User-chosen reasoning effort variant (e.g. "low", "medium", "high").
    /// `nil` uses model default via `resolveVariant()`.
    @Published private(set) var selectedReasoningVariant: String?
    /// Set while a provider API-key write/removal is in flight (drives Settings UI).
    @Published private(set) var isUpdatingAuth = false

    /// Terminal (PTY) state. `ptys` are the running pseudo-terminals, `shells` the
    /// shells the server offers, `activePtyID` the one shown in the Terminal tab.
    @Published private(set) var ptys: [OCPty] = []
    @Published private(set) var shells: [OCShell] = []
    @Published var activePtyID: String?
    @Published private(set) var isLoadingTerminal = false

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
    private var fileSearchTask: Task<Void, Never>?

    init(servers: ServerStore? = nil) {
        self.servers = servers ?? ServerStore()
        loadModelAgentPreferences()
        loadPinnedSessions()
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
        fileSearchTask?.cancel()
        fileSearchTask = nil
        activeSessionIDs.removeAll()
        pendingPermissions.removeAll()
        vcsInfo = nil
        gitFiles = []
        fileChildren = [:]
        expandedDirs = []
        loadingDirs = []
        openFiles = []
        activeFilePath = nil
        fileQuery = ""
        fileSearchResults = []
        ptys = []
        shells = []
        activePtyID = nil
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

    /// Re-fetch providers (and their connected/auth state) after an auth change.
    func reloadProviders() async {
        guard let client else { return }
        if let p = try? await client.listProviders() { providers = p }
    }

    // MARK: - Model & agent selection

    private static let modelDefaultsKey = "korbo.selectedModel"
    private static let agentDefaultsKey = "korbo.selectedAgent"
    private static let reasoningVariantDefaultsKey = "korbo.reasoningVariant"
    private static let groupingDefaultsKey = "korbo.sessionGrouping"
    private static let sortDefaultsKey = "korbo.sessionSort"

    private func loadModelAgentPreferences() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.modelDefaultsKey),
           let ref = try? JSONDecoder().decode(OCModelRef.self, from: data) {
            selectedModelOverride = ref
        }
        selectedAgentName = defaults.string(forKey: Self.agentDefaultsKey)
        selectedReasoningVariant = defaults.string(forKey: Self.reasoningVariantDefaultsKey)
        if let raw = defaults.string(forKey: Self.groupingDefaultsKey),
           let g = SessionGrouping(rawValue: raw) { sessionGrouping = g }
        if let raw = defaults.string(forKey: Self.sortDefaultsKey),
           let s = SessionSort(rawValue: raw) { sessionSort = s }
    }

    /// Choose the model for new prompts. Pass `nil` to fall back to auto-resolution.
    func selectModel(_ ref: OCModelRef?) {
        selectedModelOverride = ref
        let defaults = UserDefaults.standard
        if let ref, let data = try? JSONEncoder().encode(ref) {
            defaults.set(data, forKey: Self.modelDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.modelDefaultsKey)
        }
    }

    /// Choose the agent for new prompts. Pass `nil` to use the server default.
    func selectAgent(_ name: String?) {
        selectedAgentName = name
        let defaults = UserDefaults.standard
        if let name { defaults.set(name, forKey: Self.agentDefaultsKey) }
        else { defaults.removeObject(forKey: Self.agentDefaultsKey) }
    }

    /// Choose the reasoning variant for new prompts. Pass `nil` to use model default.
    func selectReasoningVariant(_ variant: String?) {
        selectedReasoningVariant = variant
        let defaults = UserDefaults.standard
        if let variant { defaults.set(variant, forKey: Self.reasoningVariantDefaultsKey) }
        else { defaults.removeObject(forKey: Self.reasoningVariantDefaultsKey) }
    }

    /// Agents the user can pick as the primary driver of a conversation:
    /// `primary`/`all` modes only (subagents are invoked by the model, not chosen
    /// here), and not `hidden` (opencode marks internal agents like
    /// compaction/summary/title as hidden).
    var selectableAgents: [OCAgent] {
        agents.filter { ($0.mode ?? "all") != "subagent" && !($0.hidden ?? false) }
    }

    /// Connected providers (those the server can actually reach) in a stable,
    /// preference-ordered list for the model picker.
    var connectedProviders: [OCProvider] {
        guard let providers else { return [] }
        let preferred = ["github-copilot", "anthropic", "openai", "opencode"]
        let order = preferred.filter { providers.connected.contains($0) }
            + providers.connected.filter { !preferred.contains($0) }
        return order.compactMap { id in providers.all.first { $0.id == id } }
    }

    /// The OCModel object for the currently effective model, if resolvable.
    func effectiveModelObject() -> OCModel? {
        guard let ref = resolveModel(),
              let provider = providers?.all.first(where: { $0.id == ref.providerID }),
              let model = provider.models?[ref.modelID] else { return nil }
        return model
    }

    /// Resolve the reasoning variant to send with a prompt:
    /// - `nil` for non-reasoning models.
    /// - User override if valid for the current model.
    /// - Otherwise: prefer "medium", else the middle variant, else first.
    func resolveVariant() -> String? {
        guard let model = effectiveModelObject(), model.supportsReasoning else { return nil }
        let names = model.variantNames
        if let override = selectedReasoningVariant, names.contains(override) {
            return override
        }
        if names.contains("medium") { return "medium" }
        if !names.isEmpty { return names[names.count / 2] }
        return names.first
    }

    /// Human-friendly label for a model reference (its display name if known).
    func modelDisplayName(_ ref: OCModelRef) -> String {
        providers?.all.first { $0.id == ref.providerID }?
            .models?[ref.modelID]?.name ?? ref.modelID
    }

    /// Short label for the currently effective model (override → session → auto).
    var effectiveModelLabel: String {
        if let ref = resolveModel() { return modelDisplayName(ref) }
        return "Auto"
    }

    /// Token usage for the most recent assistant turn in the selected session.
    /// This reflects the live context-window footprint (input + cache + output).
    var latestUsage: OCMessage.Usage? {
        messages.last { $0.info.role == .assistant && ($0.info.tokens?.resolvedTotal ?? 0) > 0 }?
            .info.tokens
    }

    /// Context-window size (in tokens) of the model behind the latest assistant
    /// turn, falling back to the effective model. `nil` when unknown.
    var contextLimit: Int? {
        let ref: OCModelRef?
        if let last = messages.last(where: { $0.info.role == .assistant && $0.info.modelID != nil }),
           let pid = last.info.providerID, let mid = last.info.modelID {
            ref = OCModelRef(providerID: pid, modelID: mid)
        } else {
            ref = resolveModel()
        }
        guard let ref,
              let limit = providers?.all.first(where: { $0.id == ref.providerID })?
                .models?[ref.modelID]?.limit?.context, limit > 0 else { return nil }
        return Int(limit)
    }

    /// The agent name to send with a prompt: the explicit override if still valid,
    /// else the first selectable agent the server reports.
    func resolveAgent() -> String? {
        if let name = selectedAgentName,
           selectableAgents.contains(where: { $0.name == name }) {
            return name
        }
        return selectableAgents.first?.name
    }

    // MARK: - Provider auth

    /// `PUT /auth/{id}` — store an API key for a provider, then refresh provider
    /// state so the new connection shows up. Returns whether it succeeded.
    @discardableResult
    func addProviderKey(_ providerID: String, key: String) async -> Bool {
        guard let client else { return false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        isUpdatingAuth = true
        defer { isUpdatingAuth = false }
        do {
            let ok = try await client.setProviderAPIKey(providerID, key: trimmed)
            await reloadProviders()
            return ok
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// `DELETE /auth/{id}` — remove a provider's stored credentials, then refresh.
    func removeProviderKey(_ providerID: String) async {
        guard let client else { return }
        isUpdatingAuth = true
        defer { isUpdatingAuth = false }
        do {
            _ = try await client.removeProviderAuth(providerID)
            await reloadProviders()
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    func selectSession(_ id: String) async {
        selectedSessionID = id
        await loadMessages(sessionID: id)
    }

    // MARK: - Terminal (PTY)

    /// The connected client, exposed so the Terminal view can open the PTY
    /// WebSocket directly (live I/O is owned by the view, REST control by the store).
    var activeClient: OpencodeClient? { client }

    /// Load available shells and any already-running PTY sessions; pick an active one.
    func loadTerminal() async {
        guard let client else { return }
        isLoadingTerminal = true
        defer { isLoadingTerminal = false }
        async let shellsResult = try? client.listShells()
        async let ptysResult = try? client.listPtys()
        shells = await shellsResult ?? []
        ptys = await ptysResult ?? []
        if activePtyID == nil || !ptys.contains(where: { $0.id == activePtyID }) {
            activePtyID = ptys.first?.id
        }
    }

    /// Spawn a new PTY (optionally with a specific shell) and select it.
    func newPty(command: String? = nil) async {
        guard let client else { return }
        do {
            let pty = try await client.createPty(command: command)
            ptys.append(pty)
            activePtyID = pty.id
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Kill a PTY and drop it from the list, re-selecting another if needed.
    func killPty(_ id: String) async {
        guard let client else { return }
        do {
            _ = try await client.killPty(id)
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
        ptys.removeAll { $0.id == id }
        if activePtyID == id { activePtyID = ptys.first?.id }
    }

    /// Inform the server of a terminal resize (cols/rows) so output wraps correctly.
    func resizePty(_ id: String, rows: Int, cols: Int) async {
        guard let client else { return }
        _ = try? await client.resizePty(id, rows: rows, cols: cols)
    }

    /// Surface a live terminal/WebSocket error to the rest of the UI.
    func reportTerminalError(_ message: String) {
        lastError = "Terminal: \(message)"
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

    // MARK: - Files (read-only explorer)

    /// Load the workspace root once; safe to call on every tab appearance.
    func loadFileRootIfNeeded() async {
        guard client != nil, fileChildren["."] == nil, !loadingDirs.contains(".") else { return }
        await loadDir(".")
    }

    /// Fetch one directory level into `fileChildren`.
    private func loadDir(_ path: String) async {
        guard let client else { return }
        loadingDirs.insert(path)
        defer { loadingDirs.remove(path) }
        do {
            let nodes = try await client.listFiles(path: path)
            fileChildren[path] = sortNodes(nodes)
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Expand/collapse a directory, lazily loading its children on first expand.
    func toggleDir(_ node: OCFileNode) async {
        let path = node.path
        if expandedDirs.contains(path) {
            expandedDirs.remove(path)
        } else {
            expandedDirs.insert(path)
            if fileChildren[path] == nil { await loadDir(path) }
        }
    }

    /// Currently focused open file, if any.
    var activeFile: OpenFile? {
        guard let activeFilePath else { return nil }
        return openFiles.first { $0.path == activeFilePath }
    }

    /// Open a file in the viewer. If already open, just focus its tab; otherwise
    /// add a tab, focus it, and lazily load its content.
    func openFile(_ path: String) async {
        guard let client else { return }
        if openFiles.contains(where: { $0.path == path }) {
            activeFilePath = path
            return
        }
        openFiles.append(OpenFile(path: path, content: nil, isLoading: true))
        activeFilePath = path
        do {
            let content = try await client.readFile(path: path)
            updateOpenFile(path) { $0.content = content; $0.isLoading = false }
        } catch {
            updateOpenFile(path) { $0.isLoading = false }
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Close one tab. Focus moves to the neighbouring tab (or the browser when
    /// none remain).
    func closeFile(_ path: String) {
        guard let idx = openFiles.firstIndex(where: { $0.path == path }) else { return }
        openFiles.remove(at: idx)
        guard activeFilePath == path else { return }
        if openFiles.isEmpty {
            activeFilePath = nil
        } else {
            activeFilePath = openFiles[min(idx, openFiles.count - 1)].path
        }
    }

    /// Close every tab and return to the browser.
    func closeAllFiles() {
        openFiles = []
        activeFilePath = nil
    }

    func focusFile(_ path: String) { activeFilePath = path }

    private func updateOpenFile(_ path: String, _ mutate: (inout OpenFile) -> Void) {
        guard let idx = openFiles.firstIndex(where: { $0.path == path }) else { return }
        mutate(&openFiles[idx])
    }

    /// Debounced file-path search; call on each `fileQuery` change.
    func scheduleFileSearch() {
        fileSearchTask?.cancel()
        let query = fileQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            fileSearchResults = []
            isSearchingFiles = false
            return
        }
        isSearchingFiles = true
        fileSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await self?.runFileSearch(query)
        }
    }

    private func runFileSearch(_ query: String) async {
        guard let client else { return }
        defer { isSearchingFiles = false }
        do {
            let results = try await client.findFiles(query: query)
            guard !Task.isCancelled else { return }
            fileSearchResults = results
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// One-shot fuzzy file search for composer `@` mentions (independent of the
    /// Files-tab search state). Returns `[]` on error.
    func findFiles(_ query: String, limit: Int = 8) async -> [String] {
        guard let client else { return [] }
        return (try? await client.findFiles(query: query, limit: limit)) ?? []
    }

    /// Build a composer attachment from a workspace file referenced via an `@`
    /// mention. Returns `nil` for binary/unreadable files so the caller can fall
    /// back to inserting the path as plain text. The file's text is embedded as a
    /// data URL (the same proven mechanism as picked-file attachments) so the
    /// agent receives its contents.
    func fileMentionAttachment(path: String) async -> ComposerAttachment? {
        guard let client else { return nil }
        do {
            let file = try await client.readFile(path: path)
            guard !file.isBinary, let text = file.content else { return nil }
            let mime = "text/plain"
            let b64 = Data(text.utf8).base64EncodedString()
            return ComposerAttachment(filename: path, mime: mime,
                                      dataURL: "data:\(mime);base64,\(b64)")
        } catch {
            return nil
        }
    }

    /// One-shot fuzzy file search for the command palette. Independent of the
    /// Files-pane search state so the two don't interfere.
    func paletteFileSearch(_ query: String, limit: Int = 25) async -> [String] {
        guard let client else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return (try? await client.findFiles(query: q, limit: limit)) ?? []
    }

    /// Directories first, then case-insensitive name order.
    private func sortNodes(_ nodes: [OCFileNode]) -> [OCFileNode] {
        nodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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

    /// User-pinned session IDs, persisted across launches. Pinned sessions are
    /// surfaced in a dedicated group at the top of the sidebar.
    @Published private(set) var pinnedSessionIDs: Set<String> = []

    private static let pinnedKey = "korbo.pinnedSessions"

    private func loadPinnedSessions() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.pinnedKey) ?? []
        pinnedSessionIDs = Set(stored)
    }

    func isPinned(_ id: String) -> Bool { pinnedSessionIDs.contains(id) }

    /// Pin or unpin a session (client-local; opencode has no pin concept).
    func setPinned(_ id: String, pinned: Bool) {
        if pinned { pinnedSessionIDs.insert(id) } else { pinnedSessionIDs.remove(id) }
        UserDefaults.standard.set(Array(pinnedSessionIDs), forKey: Self.pinnedKey)
    }

    func togglePin(_ id: String) { setPinned(id, pinned: !isPinned(id)) }

    /// Root sessions (sub-sessions/forks are hidden from the top list) matching
    /// the current `sessionQuery`, grouped per `sessionGrouping` and ordered per
    /// `sessionSort`.
    var sessionGroups: [SessionGroup] {
        let q = sessionQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = sessions.filter { session in
            guard (session.parentID ?? "").isEmpty else { return false }
            guard !q.isEmpty else { return true }
            return (session.title ?? "").lowercased().contains(q)
                || (session.projectName ?? "").lowercased().contains(q)
        }
        switch sessionGrouping {
        case .recency: return recencyGroups(visible)
        case .project: return projectGroups(visible)
        }
    }

    private func sortedSessions(_ items: [OCSession]) -> [OCSession] {
        switch sessionSort {
        case .recent:
            return items.sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        case .name:
            return items.sorted {
                ($0.title ?? "Untitled session").localizedCaseInsensitiveCompare($1.title ?? "Untitled session") == .orderedAscending
            }
        }
    }

    private func recencyGroups(_ visible: [OCSession]) -> [SessionGroup] {
        var buckets: [SessionBucket: [OCSession]] = [:]
        for session in visible {
            buckets[bucket(for: session), default: []].append(session)
        }
        return SessionBucket.allCases.compactMap { b in
            guard let items = buckets[b], !items.isEmpty else { return nil }
            return SessionGroup(id: b.id, title: b.title, sessions: sortedSessions(items), bucket: b)
        }
    }

    private func projectGroups(_ visible: [OCSession]) -> [SessionGroup] {
        let active = visible.filter { !$0.isArchived }
        let archived = visible.filter { $0.isArchived }
        var byProject: [String: [OCSession]] = [:]
        for session in active {
            byProject[session.projectName ?? "No project", default: []].append(session)
        }
        // Order project groups by their most-recent activity (most active first).
        var groups: [SessionGroup] = byProject.map { name, items in
            SessionGroup(id: "project:\(name)", title: name, sessions: sortedSessions(items), bucket: nil)
        }
        .sorted { a, b in
            (a.sessions.first?.lastActivity ?? .distantPast) > (b.sessions.first?.lastActivity ?? .distantPast)
        }
        if !archived.isEmpty {
            groups.append(SessionGroup(id: SessionBucket.archived.id,
                                       title: SessionBucket.archived.title,
                                       sessions: sortedSessions(archived), bucket: .archived))
        }
        return groups
    }

    private func bucket(for session: OCSession) -> SessionBucket {
        if session.isArchived { return .archived }
        if pinnedSessionIDs.contains(session.id) { return .pinned }
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

    /// `POST /session/{id}/fork` — duplicate a session, insert the new copy, and
    /// select it. Returns the new session so callers can react (e.g. focus it).
    @discardableResult
    func forkSession(_ id: String) async -> OCSession? {
        guard let client else { return nil }
        do {
            let fork = try await client.forkSession(id)
            upsertSession(fork)
            await selectSession(fork.id)
            return fork
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// `POST /session/{id}/share` — publish a public link, merge the updated
    /// session, and return the share URL.
    @discardableResult
    func shareSession(_ id: String) async -> String? {
        guard let client else { return nil }
        do {
            let updated = try await client.shareSession(id)
            upsertSession(updated)
            return updated.shareURL
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// `DELETE /session/{id}/share` — revoke the public link.
    func unshareSession(_ id: String) async {
        guard let client else { return }
        do {
            let updated = try await client.unshareSession(id)
            upsertSession(updated)
        } catch {
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Run a registered `/command` against the selected session. Like `sendPrompt`,
    /// the reply streams over `/global/event`; mark active immediately and reload
    /// once so the command's user message renders.
    func runCommand(_ command: String, arguments: String) async {
        guard let client, let sid = selectedSessionID else { return }
        activeSessionIDs.insert(sid)
        do {
            try await client.runCommand(sessionID: sid, command: command,
                                        arguments: arguments,
                                        agent: resolveAgent(), model: resolveModel())
            await loadMessages(sessionID: sid)
        } catch {
            activeSessionIDs.remove(sid)
            lastError = (error as? OpencodeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Whether `text` is a bare `/command` invocation matching a known command.
    /// Returns the command name and trailing arguments when it is.
    func parseCommand(_ text: String) -> (name: String, arguments: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), trimmed.count > 1 else { return nil }
        let body = trimmed.dropFirst()
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(parts[0])
        guard commands.contains(where: { $0.name == name }) else { return nil }
        let args = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        return (name, args)
    }

    // MARK: - Session delete

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
    func sendPrompt(_ text: String, attachments: [ComposerAttachment] = []) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client, let sid = selectedSessionID else { return }
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        var parts: [[String: Any]] = []
        if !trimmed.isEmpty {
            parts.append(["type": "text", "text": trimmed])
        }
        for attachment in attachments {
            parts.append([
                "type": "file",
                "mime": attachment.mime,
                "filename": attachment.filename,
                "url": attachment.dataURL
            ])
        }
        var body: [String: Any] = ["parts": parts]
        if let model = resolveModel() {
            body["model"] = ["providerID": model.providerID, "modelID": model.modelID]
        }
        if let agent = resolveAgent() {
            body["agent"] = agent
        }
        if let variant = resolveVariant() {
            body["variant"] = variant
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

    /// Best-effort model selection for a new prompt:
    /// 1. the user's explicit picker override, if set;
    /// 2. the session's last-used model, if any;
    /// 3. otherwise a connected provider (preferring github-copilot, then other
    ///    common hosts) paired with the opencode-recommended default model.
    func resolveModel() -> OCModelRef? {
        if let override = selectedModelOverride { return override }
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
    case pinned, today, yesterday, week, older, archived
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pinned:    return "Pinned"
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
    let id: String
    let title: String
    let sessions: [OCSession]
    /// Recency bucket when grouped by recency; `nil` for project groups.
    var bucket: SessionBucket?
}

/// How sessions in the sidebar are grouped.
enum SessionGrouping: String, CaseIterable, Identifiable {
    case recency, project
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recency: return "Recency"
        case .project: return "Project"
        }
    }
    var icon: String {
        switch self {
        case .recency: return "clock"
        case .project: return "folder"
        }
    }
}

/// How sessions within a group are ordered.
enum SessionSort: String, CaseIterable, Identifiable {
    case recent, name
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: return "Most recent"
        case .name: return "Name"
        }
    }
    var icon: String {
        switch self {
        case .recent: return "arrow.down.circle"
        case .name: return "textformat"
        }
    }
}
