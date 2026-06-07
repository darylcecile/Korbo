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

    /// Persisted `instanceID → ServerConfig.id` map so a reconnect reuses the
    /// same Keychain bearer entry rather than leaking a new server each time.
    private static let serverIDMapKey = "korbo.cloud.serverIDByInstance.v1"
    private var serverIDByInstance: [String: String]

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
        self.serverIDByInstance = UserDefaults.standard
            .dictionary(forKey: Self.serverIDMapKey) as? [String: String] ?? [:]
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
            name: "Cloud · \(instance.id)",
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

    /// Return a stable `ServerConfig.id` for an instance, persisting newly
    /// minted UUIDs so the Keychain bearer entry is reused across reconnects.
    private func stableServerID(for instanceID: String) -> UUID {
        if let existing = serverIDByInstance[instanceID], let uuid = UUID(uuidString: existing) {
            return uuid
        }
        let uuid = UUID()
        serverIDByInstance[instanceID] = uuid.uuidString
        UserDefaults.standard.set(serverIDByInstance, forKey: Self.serverIDMapKey)
        return uuid
    }

    private func setError(_ error: Error) {
        lastError = (error as? CloudError)?.errorDescription ?? error.localizedDescription
    }
}
