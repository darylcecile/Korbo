import Foundation
import AuthenticationServices
import UIKit

/// Drives the GitHub sign-in flow via `ASWebAuthenticationSession`. Opens
/// `CloudConfig.authStartURL` and waits for a redirect to the native callback
/// scheme, parsing the bearer token from the URL fragment (preferred) or query.
@MainActor
final class CloudAuthController: NSObject, ASWebAuthenticationPresentationContextProviding {

    /// Runs the web sign-in session and returns the parsed bearer token.
    ///
    /// NOTE: This depends on the backend redirecting to
    /// `\(CloudConfig.nativeCallbackURLString)#token=<token>` (or `?token=`).
    /// Until that redirect is live, use `CloudStore.signIn(pastedToken:)`.
    func signIn() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: CloudConfig.authStartURL,
                callbackURLScheme: CloudConfig.nativeCallbackScheme
            ) { callbackURL, error in
                if let error {
                    if let asError = error as? ASWebAuthenticationSessionError,
                       asError.code == .canceledLogin {
                        continuation.resume(throwing: CloudError.authCancelled)
                    } else {
                        continuation.resume(throwing: CloudError.transport(error))
                    }
                    return
                }
                guard let callbackURL,
                      let token = Self.parseToken(from: callbackURL) else {
                    continuation.resume(throwing: CloudError.invalidToken)
                    return
                }
                continuation.resume(returning: token)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    /// Extracts a `token` value from the callback URL, checking the fragment
    /// first (`#token=...`) then the query (`?token=...`).
    static func parseToken(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if let fragment = components.fragment,
           let token = tokenValue(inQueryString: fragment) {
            return token
        }
        if let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
           !token.isEmpty {
            return token
        }
        return nil
    }

    /// Parses a `token` value from a `key=value&...` encoded string.
    private static func tokenValue(inQueryString string: String) -> String? {
        var fragmentComponents = URLComponents()
        fragmentComponents.percentEncodedQuery = string
        if let token = fragmentComponents.queryItems?.first(where: { $0.name == "token" })?.value,
           !token.isEmpty {
            return token
        }
        return nil
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        if let keyWindow = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first {
            return keyWindow
        }
        return ASPresentationAnchor()
    }
}
