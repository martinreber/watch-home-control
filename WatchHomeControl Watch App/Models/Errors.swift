// Models/Errors.swift — error and feedback types.
//
// Normalized error and UI-feedback types shared across the networking layer and
// the @Observable view models. `APIError` is the single error type every Backend
// interaction funnels into; view models translate it into German feedback and
// routing decisions.

import Foundation

/// Normalized error for every Backend interaction. `LiveAPIClient` maps all
/// transport, HTTP, and decode failures into one of these cases.
enum APIError: Error, Equatable {
    /// Request exceeded its per-call deadline (5s health/lamp-state, 10s others)
    /// or was cancelled.
    case timeout
    /// HTTP 401 — an invalid or expired API_Key (Auth_Error).
    case unauthorized
    /// Any other non-2xx HTTP status.
    case http(status: Int)
    /// A transport/connection failure; carries a description of the underlying error.
    case network(String)
    /// The response body could not be decoded into the expected shape.
    case decoding
}

/// Validation and redeem failures raised by the pairing-code setup flow.
///
/// Conforms to `Error` so it can be used as the `Failure` type of `Result`
/// (see `URLValidator.validate`), which the standard library constrains to `Error`.
enum SetupError: Error, Equatable {
    /// The submitted Pairing_Code was not exactly 6 decimal digits (Req 1.5, 12.3).
    case malformedCode
    /// The submitted Base_URL was not a syntactically valid absolute http(s) URL (Req 1.8).
    case invalidURL
    /// Redeem rejected the code as invalid or expired — HTTP 401 (Req 12.4).
    case codeInvalid
    /// Redeem was rate-limited — HTTP 429 (Req 12.5).
    case tooManyAttempts
    /// Redeem exceeded its 10s deadline (Req 12.6).
    case redeemTimeout
    /// Any other redeem failure (other non-2xx, network, or decode error).
    case redeemFailed
}

/// Non-blocking German feedback banner shown after a command completes.
struct Feedback: Equatable {
    enum Kind { case success, error }
    let kind: Kind
    let message: String
}

/// Backend reachability state driven by the launch/retry health check.
enum HealthState: Equatable {
    case checking
    case reachable
    case unreachable(String)
}
