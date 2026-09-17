// Networking/RequestBuilder.swift — pure endpoint → URLRequest mapping.
//
// `RequestBuilder` is the pure, I/O-free seam that turns an `Endpoint` plus the
// configured Base_URL and API key into a concrete `URLRequest`. Keeping request
// construction (path, method, headers, body) separate from `URLSession` makes it
// unit- and property-testable without a network (Property 1/2).
//
// Mapping (Req 2.1, 3.1, 4.2, 4.3, 6.1, 6.2, 8.1–8.3, 11.1, 11.3):
//   .health        -> GET  /health                       (no X-API-Key, no body)
//   .blind         -> POST /blind                         { "action": "up"|"down" }
//   .lamps         -> GET  /lamps
//   .lampState     -> POST /lamps/{id}/state              { "power": true|false }
//   .speakers      -> GET  /sonos/speakers
//   .speakerPlay   -> POST /sonos/speakers/{id}/play      (no body)
//   .speakerPause  -> POST /sonos/speakers/{id}/pause     (no body)
//   .speakerRadio  -> POST /sonos/speakers/{id}/radio     { uri, metadata, name }
//   .redeem        -> POST /pairing/redeem                { "code": <code> } (no X-API-Key)
//
// `X-API-Key` is attached to every endpoint except `.health` and `.redeem`.
// `Content-Type: application/json` is set only on body-bearing endpoints.

import Foundation

/// Builds a concrete `URLRequest` for an `Endpoint` against a fixed Base_URL.
///
/// Pure and free of I/O: `build(_:apiKey:)` performs no network access, so it can
/// be exhaustively property-tested.
struct RequestBuilder {
    /// The configured Base_URL (e.g. `http://192.168.1.122:8080`).
    let baseURL: URL

    /// HTTP methods used by the Backend contract.
    private enum Method: String {
        case get = "GET"
        case post = "POST"
    }

    /// JSON body for `POST /blind` — `{ "action": "up"|"down" }`.
    private struct BlindBody: Encodable {
        let action: BlindAction
    }

    /// JSON body for `POST /lamps/{id}/state` — `{ "power": true|false }`.
    private struct LampStateBody: Encodable {
        let power: Bool
    }

    /// JSON body for `POST /pairing/redeem` — `{ "code": <code> }`.
    private struct RedeemBody: Encodable {
        let code: String
    }

    /// Maps an `Endpoint` to a fully formed `URLRequest`.
    ///
    /// - Parameters:
    ///   - endpoint: The Backend operation to invoke.
    ///   - apiKey: The stored API_Key. Attached as `X-API-Key` on every endpoint
    ///     except `.health`; ignored (and may be `nil`) for `.health`.
    /// - Returns: A `URLRequest` with the endpoint's URL, method, headers, and body.
    /// - Throws: `APIError.network` when a URL cannot be formed, or a JSON encoding
    ///   error when a body cannot be serialized.
    func build(_ endpoint: Endpoint, apiKey: String?) throws -> URLRequest {
        switch endpoint {
        case .health:
            // The only unauthenticated endpoint: no X-API-Key, no body (Req 3.1).
            return try makeRequest(method: .get, path: "/health", attachKey: nil)

        case .blind(let action):
            return try makeRequest(
                method: .post,
                path: "/blind",
                attachKey: apiKey,
                body: BlindBody(action: action)
            )

        case .lamps:
            return try makeRequest(method: .get, path: "/lamps", attachKey: apiKey)

        case .lampState(let id, let power):
            return try makeRequest(
                method: .post,
                path: "/lamps/\(pathEscaped(id))/state",
                attachKey: apiKey,
                body: LampStateBody(power: power)
            )

        case .speakers:
            return try makeRequest(method: .get, path: "/sonos/speakers", attachKey: apiKey)

        case .speakerPlay(let id):
            return try makeRequest(
                method: .post,
                path: "/sonos/speakers/\(pathEscaped(id))/play",
                attachKey: apiKey
            )

        case .speakerPause(let id):
            return try makeRequest(
                method: .post,
                path: "/sonos/speakers/\(pathEscaped(id))/pause",
                attachKey: apiKey
            )

        case .speakerRadio(let id, let request):
            return try makeRequest(
                method: .post,
                path: "/sonos/speakers/\(pathEscaped(id))/radio",
                attachKey: apiKey,
                body: request
            )

        case .redeem(let code):
            // Unauthenticated like .health: no X-API-Key header (Req 12.1).
            return try makeRequest(
                method: .post,
                path: "/pairing/redeem",
                attachKey: nil,
                body: RedeemBody(code: code)
            )
        }
    }

    // MARK: - Helpers

    /// Builds a bodyless request (GET, or POST with no payload).
    private func makeRequest(method: Method, path: String, attachKey apiKey: String?) throws -> URLRequest {
        var request = URLRequest(url: try url(for: path))
        request.httpMethod = method.rawValue
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        return request
    }

    /// Builds a request carrying a JSON body; sets `Content-Type: application/json`.
    private func makeRequest(
        method: Method,
        path: String,
        attachKey apiKey: String?,
        body: some Encodable
    ) throws -> URLRequest {
        var request = try makeRequest(method: method, path: path, attachKey: apiKey)
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Resolves a path against the Base_URL into an absolute URL.
    private func url(for path: String) throws -> URL {
        guard let resolved = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.network("Ungültige URL für Pfad \(path)")
        }
        return resolved
    }

    /// Percent-encodes a path segment (e.g. a Sonos `RINCON_...` id) so it is safe
    /// to interpolate into a URL path.
    private func pathEscaped(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? segment
    }
}
