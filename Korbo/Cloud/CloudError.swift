import Foundation

/// Decodes the backend's error envelope: `{ error: { code, message, ... } }`.
struct CloudErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
        let httpStatus: Int?
        let instanceId: String?
        let retryable: Bool?
        let retryAfterSeconds: Int?
        let docs: String?
    }

    let error: Payload
}

/// Errors thrown by the Korbo Cloud management client and store.
enum CloudError: LocalizedError {
    /// A structured backend error envelope.
    case envelope(
        code: String,
        message: String,
        httpStatus: Int,
        retryable: Bool,
        retryAfterSeconds: Int?,
        instanceId: String?
    )
    /// A non-2xx response with no decodable envelope (status, raw body snippet).
    case http(Int, String)
    /// A URLSession / connectivity failure.
    case transport(Error)
    /// No bearer token is stored.
    case notSignedIn
    /// The token was rejected (401) or failed validation.
    case invalidToken
    /// The user cancelled the web sign-in flow.
    case authCancelled

    var errorDescription: String? {
        switch self {
        case let .envelope(code, message, httpStatus, _, _, _):
            return message.isEmpty ? "Korbo Cloud error (\(code), HTTP \(httpStatus))." : message
        case let .http(status, body):
            let extra = body.isEmpty ? "" : " — \(body.prefix(200))"
            return "Korbo Cloud returned HTTP \(status).\(extra)"
        case let .transport(error):
            return "Could not reach Korbo Cloud: \(error.localizedDescription)"
        case .notSignedIn:
            return "You're not signed in to Korbo Cloud."
        case .invalidToken:
            return "Your Korbo Cloud session is invalid. Sign in again."
        case .authCancelled:
            return "Sign-in was cancelled."
        }
    }

    /// Whether the backend marked the error as retryable.
    var retryable: Bool {
        switch self {
        case let .envelope(_, _, _, retryable, _, _): return retryable
        case .transport:                              return true
        default:                                      return false
        }
    }

    /// The backend error code, when present.
    var code: String? {
        switch self {
        case let .envelope(code, _, _, _, _, _): return code
        default:                                 return nil
        }
    }
}
