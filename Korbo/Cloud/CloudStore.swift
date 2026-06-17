import Foundation
import SwiftUI

/// `@MainActor` ObservableObject backing the Korbo Cloud integration. Owns the
/// token store, the management client, the web sign-in controller, and a weak
/// reference to the existing `KorboStore` (used to connect to a provisioned
/// instance). All networking flows through the `KorboCloudClient` actor.
///
/// The public API here is the contract UI layers compile against — keep the
/// method signatures stable.
@MainActor
final class CloudStore: ObservableObject {

    // MARK: Published state

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var me: CloudUser?
    @Published private(set) var balance: CloudBalance?
    @Published private(set) var instances: [CloudInstance] = []
    /// Self-hosted ("bring your own machine") sessions registered via the `korbo`
    /// CLI. Listed alongside managed `instances` but free and connection-gated on
    /// a simple online/offline `status`.
    @Published private(set) var sessions: [CloudSession] = []
    @Published private(set) var isBusy: Bool = false
    @Published var lastError: String?

    /// A one-shot, user-dismissable notice about how the workspace was restored
    /// on the instance we just connected to (e.g. it was re-cloned from origin
    /// because no snapshot was available, so local-only edits weren't carried
    /// over). `nil` when there's nothing noteworthy to surface.
    @Published var workspaceNotice: WorkspaceNotice?

    /// Why the connected instance's workspace differs from what the user may
    /// expect after a resume. Surfaced as a dismissable banner.
    enum WorkspaceNotice: Equatable {
        /// No snapshot was available, so the repo was freshly re-cloned from
        /// origin. Any uncommitted local-only files from before the last sleep
        /// are gone.
        case reclonedFromOrigin
        /// The workspace was restored faithfully, but from a snapshot that may
        /// predate the user's most recent edits (a prior suspend couldn't snapshot).
        case restoredStale
    }

    // MARK: Collaborators

    private let tokenStore: CloudTokenStore
    private let client: KorboCloudClient
    private let auth: CloudAuthController
    private weak var korbo: KorboStore?

    /// Persisted `resourceID → ServerConfig.id` map so a reconnect reuses the
    /// same Keychain bearer entry rather than leaking a new server each time. The
    /// `resourceID` is either a managed instance id (`inst-…`) or a self-hosted
    /// session id (`byo-…`); both are globally unique so they share one map.
    private static let serverIDMapKey = "korbo.cloud.serverIDByInstance.v1"
    private var serverIDByResource: [String: String]

    /// Device-local display-name overrides for self-hosted (BYO) sessions, keyed
    /// by session id. The backend has no rename endpoint, so a custom tunnel name
    /// lives only on this device; `aliased(_:)` overlays it onto the fetched list
    /// so every `displayName` surface (picker, palette, sidebar, connected title)
    /// reflects it.
    private static let sessionAliasMapKey = "korbo.cloud.sessionAliasByID.v1"
    private var sessionAliasByID: [String: String]

    /// Raw, un-aliased session list as last fetched from the backend. `sessions`
    /// is this with local aliases overlaid; keeping the backend truth here lets a
    /// rename (or an alias clear) recompute instantly without a network round-trip
    /// or losing the server-provided name.
    private var rawSessions: [CloudSession] = []

    /// Maximum time to wait for a transitional instance to become ready.
    private let readinessTimeout: TimeInterval = 60
    private let readinessPollInterval: UInt64 = 2_000_000_000 // 2s in ns

    init() {
        let tokenStore = CloudTokenStore()
        self.tokenStore = tokenStore
        // Read the live token straight from the Keychain so the provider is
        // thread-safe and always reflects the latest sign-in/sign-out.
        self.client = KorboCloudClient(tokenProvider: {
            Keychain.get(account: CloudTokenStore.account)
        })
        self.auth = CloudAuthController()
        self.isSignedIn = tokenStore.isSignedIn
        self.serverIDByResource = UserDefaults.standard
            .dictionary(forKey: Self.serverIDMapKey) as? [String: String] ?? [:]
        self.sessionAliasByID = UserDefaults.standard
            .dictionary(forKey: Self.sessionAliasMapKey) as? [String: String] ?? [:]
    }

    /// Wire up the existing `KorboStore` so `connectToInstance` can drive the
    /// shared opencode connection.
    func attach(korbo: KorboStore) {
        self.korbo = korbo
    }

    /// On launch, if a token is present, refresh the account and instance lists.
    func bootstrap() async {
        guard tokenStore.isSignedIn else { return }
        isSignedIn = true
        await refreshMe()
        await refreshInstances()
        await refreshSessions()
    }

    // MARK: - Authentication

    /// Sign in via the GitHub web flow, store the returned token, and refresh.
    func signIn() async {
        lastError = nil
        do {
            let token = try await auth.signIn()
            tokenStore.save(token)
            isSignedIn = tokenStore.isSignedIn
            await refreshMe()
            await refreshInstances()
            await refreshSessions()
        } catch {
            isSignedIn = tokenStore.isSignedIn
            setError(error)
        }
    }

    /// Fallback sign-in: accept a pasted token and validate it via `GET /api/me`.
    ///
    /// NOTE: This exists because the backend's native-scheme redirect may not be
    /// live yet (see `CloudConfig.authStartURL`). Once that redirect lands,
    /// `signIn()` is the primary path and this remains a manual escape hatch.
    func signIn(pastedToken: String) async {
        lastError = nil
        let trimmed = pastedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = CloudError.invalidToken.errorDescription
            return
        }
        tokenStore.save(trimmed)
        isSignedIn = tokenStore.isSignedIn
        do {
            let response = try await client.me()
            me = response.user
            balance = response.balance
            await refreshInstances()
            await refreshSessions()
        } catch CloudError.invalidToken, CloudError.notSignedIn {
            tokenStore.clear()
            isSignedIn = false
            me = nil
            balance = nil
            lastError = CloudError.invalidToken.errorDescription
        } catch {
            setError(error)
        }
    }

    /// Best-effort logout: notify the backend, clear local state.
    func signOut() async {
        try? await client.logout()
        tokenStore.clear()
        isSignedIn = false
        me = nil
        balance = nil
        instances = []
        sessions = []
        rawSessions = []
        lastError = nil
        workspaceNotice = nil
    }

    // MARK: - Refresh

    /// Refresh the signed-in user and balance.
    func refreshMe() async {
        do {
            let response = try await client.me()
            me = response.user
            balance = response.balance
        } catch {
            setError(error)
        }
    }

    /// Refresh the list of provisioned instances.
    func refreshInstances() async {
        do {
            instances = try await client.listInstances()
        } catch {
            setError(error)
        }
    }

    /// Refresh the list of self-hosted (BYO) sessions. Failures are swallowed into
    /// an empty list rather than the shared `lastError`: `/api/sessions` is additive
    /// (and may be absent for accounts/backends without the feature), so a missing
    /// or failing endpoint must never surface a dashboard error to users who never
    /// touch BYO.
    func refreshSessions() async {
        rawSessions = (try? await client.listSessions()) ?? []
        sessions = aliased(rawSessions)
    }

    /// Overlay device-local aliases onto a freshly-fetched session list so every
    /// `displayName` surface reflects a tunnel the user renamed on this device.
    private func aliased(_ list: [CloudSession]) -> [CloudSession] {
        guard !sessionAliasByID.isEmpty else { return list }
        return list.map { session in
            if let alias = sessionAliasByID[session.id], !alias.isEmpty {
                return session.withName(alias)
            }
            return session
        }
    }

    /// Rename a self-hosted (BYO) session for display on this device only. An
    /// empty name clears the override, restoring the backend/default label. The
    /// backend has no rename endpoint, so this alias never leaves the device.
    func renameSession(_ id: String, to newName: String) {
        let trimmed = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        if trimmed.isEmpty {
            sessionAliasByID.removeValue(forKey: id)
        } else {
            sessionAliasByID[id] = trimmed
        }
        UserDefaults.standard.set(sessionAliasByID, forKey: Self.sessionAliasMapKey)
        sessions = aliased(rawSessions)
        // Keep any persisted server config in sync so the connection footer and
        // failure-screen title reflect the new name, not the label captured when
        // the session was first connected.
        if let serverIDString = serverIDByResource[id],
           let serverID = UUID(uuidString: serverIDString),
           let label = sessions.first(where: { $0.id == id })?.displayName {
            korbo?.servers.rename(id: serverID, to: label)
        }
    }

    // MARK: - Instance management

    func createInstance(machineType: String, repo: String?) async throws -> CloudInstance {
        let instance = try await client.createInstance(machineType: machineType, repo: repo)
        await refreshInstances()
        return instance
    }

    func deleteInstance(_ id: String) async throws {
        try await client.deleteInstance(id)
        await refreshInstances()
    }

    /// Remove a self-hosted session registration. If it's the one currently
    /// connected, tear down its saved `ServerConfig` first so the app isn't left
    /// pointed at a proxy that no longer resolves.
    func deleteSession(_ id: String) async throws {
        try await client.deleteSession(id)
        cleanupServer(forResourceID: id)
        await refreshSessions()
    }

    func instanceState(_ id: String) async throws -> CloudInstanceStateDetail {
        try await client.instanceState(id)
    }

    func installations() async throws -> [CloudInstallation] {
        try await client.installations()
    }

    func repos(installationId: Int) async throws -> [CloudRepo] {
        try await client.repos(installationId: installationId)
    }

    /// Public GitHub App install page so the user can grant Korbo access to a
    /// repo (one-tap install + repo selection) without leaving for GitHub settings.
    func installURL() async throws -> URL {
        try await client.installURL()
    }

    func topupURL(credits: Int) async throws -> URL {
        try await client.topupURL(credits: credits)
    }

    // MARK: - Connect

    /// Connect the shared opencode session to a provisioned instance's proxy.
    ///
    /// If the instance is still transitional, polls its state until it becomes
    /// ready (or reaches a terminal state) before saving the `ServerConfig` and
    /// asking `KorboStore` to connect. Progress is surfaced via `isBusy` /
    /// `lastError`.
    func connectToInstance(_ instance: CloudInstance) async {
        guard let korbo else {
            lastError = "Korbo Cloud is not attached to the app yet."
            return
        }
        guard let token = tokenStore.token, !token.isEmpty else {
            lastError = CloudError.notSignedIn.errorDescription
            return
        }
        // Ignore re-entrant requests (e.g. a second tap from the picker while a
        // connect from the command palette is already in flight) so concurrent
        // switches can't race to a nondeterministic final server selection.
        guard !isBusy else { return }
        // Dead instances can never become reachable; surface a clear error rather
        // than spinning through `waitUntilReady` to an inevitable timeout. (Call
        // sites other than the dashboard — picker, palette — don't pre-gate this.)
        guard !instance.state.isTerminal else {
            lastError = instance.reason ?? "Instance is \(instance.state.displayLabel.lowercased()) and can't be connected."
            return
        }

        isBusy = true
        lastError = nil
        workspaceNotice = nil
        defer { isBusy = false }

        if instance.state.isTransitional {
            do {
                try await waitUntilReady(instance.id)
            } catch {
                setError(error)
                return
            }
        }

        let serverID = stableServerID(for: instance.id)
        let config = ServerConfig(
            id: serverID,
            name: instance.displayName,
            baseURLString: CloudConfig.instanceBaseURLString(instance.id),
            authKind: .bearer
        )
        korbo.servers.save(config, secret: token)
        await korbo.connect()

        // Surface how the workspace was materialized (e.g. re-cloned from origin
        // on a resume with no snapshot). Best-effort and off the connect path so
        // it never delays or fails the connection itself.
        let instanceID = instance.id
        Task { [weak self] in await self?.evaluateWorkspaceRestore(instanceID) }
    }

    /// Connect the shared opencode session to a self-hosted (BYO) session's proxy.
    ///
    /// The session is reached exactly like a managed instance — `https://<proxyHost>`
    /// with the account bearer token — so this reuses the same `ServerConfig` →
    /// `KorboStore.connect()` path. There is no provisioning lifecycle to wait on;
    /// instead we re-check the session is still `online` right before connecting so
    /// a stale `online` from the cached list doesn't strand the user on a dead proxy.
    func connectToSession(_ session: CloudSession) async {
        guard let korbo else {
            lastError = "Korbo Cloud is not attached to the app yet."
            return
        }
        guard let token = tokenStore.token, !token.isEmpty else {
            lastError = CloudError.notSignedIn.errorDescription
            return
        }
        guard !isBusy else { return }
        guard let baseURLString = Self.sessionBaseURLString(for: session.proxyHost) else {
            lastError = "This machine reported an invalid address. Update the korbo CLI and try again."
            return
        }

        isBusy = true
        lastError = nil
        workspaceNotice = nil
        defer { isBusy = false }

        // Re-check liveness: a session listed as online may have gone offline since
        // the last refresh. Best-effort — if the check itself fails we fall back to
        // the cached status rather than blocking a connect on a transient API error.
        var current = session
        if let fresh = try? await client.getSession(session.id) {
            let aliasedFresh = aliased([fresh]).first ?? fresh
            current = aliasedFresh
            rawSessions = rawSessions.map { $0.id == fresh.id ? fresh : $0 }
            sessions = aliased(rawSessions)
        }
        guard current.status.isOnline else {
            lastError = "“\(session.displayName)” is offline. Start it on your machine with the korbo CLI, then try again."
            return
        }

        let serverID = stableServerID(for: session.id)
        let config = ServerConfig(
            id: serverID,
            name: session.displayName,
            baseURLString: baseURLString,
            authKind: .bearer,
            usesServerDefaultProject: true
        )
        korbo.servers.save(config, secret: token)
        await korbo.connect()
    }

    /// Poll the instance state briefly until it reports ready, then translate the
    /// backend's `workspaceRestore` / `workspaceRestoreStale` signal into a
    /// user-facing `workspaceNotice`. Entirely best-effort: any error or timeout
    /// simply leaves the notice unset.
    private func evaluateWorkspaceRestore(_ id: String) async {
        let deadline = Date().addingTimeInterval(readinessTimeout)
        while Date() < deadline {
            guard let detail = try? await client.instanceState(id) else { return }
            if detail.state.isReady {
                if detail.workspaceRestoreStale {
                    workspaceNotice = .restoredStale
                } else if detail.workspaceRestore == .reclone {
                    workspaceNotice = .reclonedFromOrigin
                } else {
                    workspaceNotice = nil
                }
                return
            }
            if detail.state.isTerminal { return }
            try? await Task.sleep(nanoseconds: readinessPollInterval)
        }
    }

    /// Dismiss the workspace-restore notice (user tapped the banner's close).
    func dismissWorkspaceNotice() {
        workspaceNotice = nil
    }

    /// Poll `instanceState` every ~2s until the instance reports ready, throwing
    /// if it reaches a terminal state or the timeout elapses.
    private func waitUntilReady(_ id: String) async throws {
        let deadline = Date().addingTimeInterval(readinessTimeout)
        while Date() < deadline {
            let detail = try await client.instanceState(id)
            if detail.state.isReady { return }
            if detail.state.isTerminal {
                throw CloudError.envelope(
                    code: "instance_\(detail.state.rawValue)",
                    message: detail.reason ?? "Instance is \(detail.state.displayLabel.lowercased()).",
                    httpStatus: 409,
                    retryable: false,
                    retryAfterSeconds: nil,
                    instanceId: id
                )
            }
            try await Task.sleep(nanoseconds: readinessPollInterval)
        }
        throw CloudError.envelope(
            code: "instance_starting",
            message: "Timed out waiting for instance \(id) to become ready.",
            httpStatus: 504,
            retryable: true,
            retryAfterSeconds: nil,
            instanceId: id
        )
    }

    // MARK: - Helpers

    /// The backend resource id (managed instance `inst-…` or self-hosted session
    /// `byo-…`) backing the currently-selected opencode server, if any. Derived
    /// from the active `ServerConfig.id` via the `resource → serverID` map, so it
    /// stays correct no matter how the server was selected (instance picker,
    /// command palette, or the footer server menu).
    private var connectedResourceID: String? {
        guard let serverID = korbo?.servers.selectedServerID?.uuidString else { return nil }
        return serverIDByResource.first(where: { $0.value == serverID })?.key
    }

    /// The managed cloud instance backing the currently-selected opencode server,
    /// if any. Classified by membership in `instances` (robust to id format) and
    /// mutually exclusive with `connectedSession` because instance/session id
    /// spaces don't overlap. Reactive in practice because connecting flips
    /// `KorboStore.status`, which redraws observers.
    var connectedInstance: CloudInstance? {
        guard let id = connectedResourceID else { return nil }
        return instances.first { $0.id == id }
    }

    /// The self-hosted (BYO) session backing the currently-selected opencode
    /// server, if any. Classified by membership in `sessions`, mutually exclusive
    /// with `connectedInstance`.
    var connectedSession: CloudSession? {
        guard let id = connectedResourceID else { return nil }
        return sessions.first { $0.id == id }
    }

    /// A short label for whatever cloud resource is currently connected (managed
    /// instance or self-hosted session), or `nil` when connected to a plain
    /// local/LAN server. Lets shared UI render a single "connected to" affordance.
    var connectedDisplayName: String? {
        connectedInstance?.displayName ?? connectedSession?.displayName
    }

    /// True when the active opencode server is a managed instance or a self-hosted
    /// session (as opposed to a manually-configured local/LAN server).
    var isConnectedToCloudResource: Bool {
        connectedResourceID != nil
    }

    /// `ServerConfig.id`s (as strings) backing an **online** self-hosted session
    /// currently in `sessions`. The footer server menu lists these sessions in a
    /// dedicated "Tunnels" section, so the plain-server list hides their saved
    /// configs to avoid a confusing duplicate row for the same session.
    var onlineSessionServerIDs: Set<String> {
        Set(sessions.filter { $0.status.isOnline }.compactMap { serverIDByResource[$0.id] })
    }

    /// Return a stable `ServerConfig.id` for a cloud resource (instance or
    /// session), persisting newly minted UUIDs so the Keychain bearer entry is
    /// reused across reconnects.
    private func stableServerID(for resourceID: String) -> UUID {
        if let existing = serverIDByResource[resourceID], let uuid = UUID(uuidString: existing) {
            return uuid
        }
        let uuid = UUID()
        serverIDByResource[resourceID] = uuid.uuidString
        UserDefaults.standard.set(serverIDByResource, forKey: Self.serverIDMapKey)
        return uuid
    }

    /// Tear down the saved `ServerConfig` for a cloud resource: remove the server
    /// (and its Keychain secret) and forget the id mapping. Used when a self-hosted
    /// session is deleted so the app isn't left selected to a dead proxy.
    private func cleanupServer(forResourceID resourceID: String) {
        guard let serverIDString = serverIDByResource[resourceID],
              let serverID = UUID(uuidString: serverIDString) else { return }
        if let config = korbo?.servers.servers.first(where: { $0.id == serverID }) {
            korbo?.servers.remove(config)
        }
        serverIDByResource[resourceID] = nil
        UserDefaults.standard.set(serverIDByResource, forKey: Self.serverIDMapKey)
    }

    /// Validate a backend-supplied `proxyHost` and build the opencode base URL.
    /// The contract specifies a bare host (no scheme, userinfo, port, path, query,
    /// or whitespace); anything else is rejected rather than constructing a
    /// malformed or foreign URL. Building via `URLComponents` and asserting the
    /// parsed host equals the input closes host-spoofing tricks like
    /// `good.host@evil.com` (whose real host is `evil.com`), which would otherwise
    /// leak the bearer token to an attacker-controlled origin.
    nonisolated static func sessionBaseURLString(for proxyHost: String) -> String? {
        let host = proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty,
              host.contains("."),
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !host.contains("://"),
              !host.contains("/"),
              !host.contains("@"),
              !host.contains("?"),
              !host.contains("#")
        else { return nil }
        guard let components = URLComponents(string: "https://\(host)"),
              components.host == host,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.path.isEmpty,
              components.query == nil,
              components.fragment == nil,
              let url = components.url
        else { return nil }
        return url.absoluteString
    }

    private func setError(_ error: Error) {
        lastError = (error as? CloudError)?.errorDescription ?? error.localizedDescription
    }
}
