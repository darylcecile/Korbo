import Foundation
import Combine

/// Stores the account-level Korbo Cloud bearer token in the Keychain. The same
/// token authenticates both the management API (`my.korbo.app`) and the
/// per-instance opencode proxies (`*.cloud.korbo.app`).
@MainActor
final class CloudTokenStore: ObservableObject {
    /// Keychain account under which the token is stored (shares the app's
    /// existing Keychain `service` bucket).
    static let account = "korbo.cloud.token"

    /// The current bearer token, or `nil` when signed out.
    @Published private(set) var token: String?

    init() {
        token = Keychain.get(account: Self.account)
    }

    /// Whether a token is currently stored.
    var isSignedIn: Bool { token != nil }

    /// Persist a token (trims whitespace; empty input is treated as a clear).
    func save(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return
        }
        Keychain.set(trimmed, account: Self.account)
        self.token = trimmed
    }

    /// Remove the stored token.
    func clear() {
        Keychain.delete(account: Self.account)
        token = nil
    }
}
