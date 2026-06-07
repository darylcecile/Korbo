import Foundation

/// Static configuration for the Korbo Cloud backend. Pure and dependency-free so
/// the hosts and auth endpoints are trivial to adjust as the backend evolves.
///
/// The management ("dashboard") API lives on `my.korbo.app`; provisioned
/// opencode instances are reached through a per-instance subdomain of
/// `cloud.korbo.app`. A single account-level bearer token authenticates both.
enum CloudConfig {
    /// Host serving the management API and the GitHub sign-in flow.
    static let dashboardHost = "my.korbo.app"

    /// Host under which per-instance opencode proxies are exposed.
    static let cloudHost = "cloud.korbo.app"

    /// `https://my.korbo.app` — base for all management (`/api/...`) calls.
    static let dashboardBaseURL = URL(string: "https://\(dashboardHost)")!

    /// Custom URL scheme the native sign-in callback redirects to.
    static let nativeCallbackScheme = "korbo"

    /// Full native callback URL passed to the backend as `return=`.
    static let nativeCallbackURLString = "korbo://auth-callback"

    /// GitHub sign-in entry point opened in `ASWebAuthenticationSession`.
    ///
    /// NOTE: The backend is expected to redirect to
    /// `\(nativeCallbackURLString)#token=<token>` (or `?token=`) on success. That
    /// native-scheme redirect may not be live yet (today it redirects to
    /// `https://my.korbo.app/#token=`), so a pasted-token fallback exists in
    /// `CloudStore.signIn(pastedToken:)`. Adjust the `return` value here once the
    /// backend honours the custom scheme.
    static let authStartURL: URL = {
        var components = URLComponents(string: "https://\(dashboardHost)/api/auth/github/start")!
        components.queryItems = [URLQueryItem(name: "return", value: nativeCallbackURLString)]
        return components.url!
    }()

    /// Base URL string for a provisioned instance's opencode proxy, e.g.
    /// `https://abc123.cloud.korbo.app`.
    static func instanceBaseURLString(_ id: String) -> String {
        "https://\(id).\(cloudHost)"
    }
}
